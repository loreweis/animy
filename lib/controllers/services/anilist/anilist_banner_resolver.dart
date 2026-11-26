import 'dart:async';
import 'dart:convert';

import 'package:anymex/controllers/cacher/cold_cache.dart';
import 'package:anymex/controllers/network/network_manager.dart';
import 'package:anymex/controllers/service_handler/service_handler.dart';
import 'package:anymex/controllers/services/anilist/anilist_rate_limiter.dart';
import 'package:anymex/database/data_keys/keys.dart';
import 'package:anymex/utils/logger.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

class _BannerLookupTask {
  final int id;
  final bool isMal;
  final bool isManga;

  const _BannerLookupTask({
    required this.id,
    required this.isMal,
    required this.isManga,
  });

  String get cacheKey =>
      '${isMal ? 'mal' : 'al'}:${isManga ? 'MANGA' : 'ANIME'}:$id';

  @override
  bool operator ==(Object other) =>
      other is _BannerLookupTask &&
      other.id == id &&
      other.isMal == isMal &&
      other.isManga == isManga;

  @override
  int get hashCode => Object.hash(id, isMal, isManga);
}

class AnilistBannerResolver {
  static final AnilistBannerResolver instance = AnilistBannerResolver._();
  AnilistBannerResolver._() {
    _hydrateFromDisk();
  }

  static const String _endpoint = 'https://graphql.anilist.co';
  static const String _diskCacheKey = 'anilist_banner_map_v1';

  final RxInt version = 0.obs;
  final Map<String, String?> _cache = {};
  final Set<_BannerLookupTask> _pending = {};
  final Set<String> _inFlightKeys = {};
  Timer? _debounce;
  bool _isDraining = false;

  http.Client get _client => NetworkManager.instance.compatibleClient;

  static bool isLandscapeBannerUrl(String? url, {String? poster}) {
    if (url == null) return false;
    final trimmed = url.trim();
    if (trimmed.isEmpty ||
        trimmed == '?' ||
        trimmed == '??' ||
        trimmed == 'null') {
      return false;
    }
    if (poster != null && trimmed == poster.trim()) {
      return false;
    }
    final lower = trimmed.toLowerCase();
    // Known portrait poster URLs that are NOT landscape banners
    if (lower.contains('myanimelist.net/images/')) return false;
    if (lower.contains('anilistcdn/media/') && lower.contains('/cover/')) {
      return false;
    }
    if (lower.contains('simkl.in/posters/')) return false;
    return true;
  }

  Future<void> _hydrateFromDisk() async {
    try {
      final raw = await ColdCache.read(_diskCacheKey);
      if (raw == null || raw.isEmpty) return;
      bool added = false;
      raw.forEach((key, value) {
        if (value is String && value.isNotEmpty && !_cache.containsKey(key)) {
          _cache[key] = value;
          added = true;
        }
      });
      if (added) {
        version.value++;
      }
    } catch (_) {}
  }

  void _persistToDisk() {
    try {
      final out = <String, dynamic>{};
      _cache.forEach((key, value) {
        if (value != null && value.isNotEmpty) {
          out[key] = value;
        }
      });
      if (out.isNotEmpty) {
        ColdCache.write(_diskCacheKey, out);
      }
    } catch (_) {}
  }

  String? _cacheKeyFor({
    required String? id,
    required ServicesType serviceType,
    required bool isManga,
  }) {
    if (id == null || id.isEmpty) return null;
    if (serviceType != ServicesType.anilist &&
        serviceType != ServicesType.mal) {
      return null;
    }
    final parsedId = int.tryParse(id.trim());
    if (parsedId == null || parsedId <= 0) return null;
    final prefix = serviceType == ServicesType.mal ? 'mal' : 'al';
    final mediaType = isManga ? 'MANGA' : 'ANIME';
    return '$prefix:$mediaType:$parsedId';
  }

  String? getCached({
    required String? id,
    required ServicesType serviceType,
    required bool isManga,
  }) {
    final key = _cacheKeyFor(
      id: id,
      serviceType: serviceType,
      isManga: isManga,
    );
    if (key == null) return null;
    return _cache[key];
  }

  String? lookupOrSchedule({
    required String? id,
    required ServicesType serviceType,
    required bool isManga,
  }) {
    final key = _cacheKeyFor(
      id: id,
      serviceType: serviceType,
      isManga: isManga,
    );
    if (key == null) return null;

    if (_cache.containsKey(key)) {
      return _cache[key];
    }

    if (!_inFlightKeys.contains(key)) {
      final parsedId = int.parse(id!.trim());
      _pending.add(
        _BannerLookupTask(
          id: parsedId,
          isMal: serviceType == ServicesType.mal,
          isManga: isManga,
        ),
      );
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 90), _drainQueue);
    }

    return null;
  }

  Future<void> _drainQueue() async {
    if (_isDraining) return;
    _isDraining = true;

    try {
      while (_pending.isNotEmpty) {
        final snapshot = _pending.toList();
        _pending.clear();

        final groups = <(bool, bool), List<_BannerLookupTask>>{};
        for (final task in snapshot) {
          if (_cache.containsKey(task.cacheKey) ||
              _inFlightKeys.contains(task.cacheKey)) {
            continue;
          }
          groups.putIfAbsent((task.isMal, task.isManga), () => []).add(task);
        }

        for (final entry in groups.entries) {
          final (isMal, isManga) = entry.key;
          final tasks = entry.value;
          for (int i = 0; i < tasks.length; i += 50) {
            final batch = tasks.sublist(
              i,
              (i + 50) > tasks.length ? tasks.length : (i + 50),
            );
            await _fetchBatch(batch, isMal: isMal, isManga: isManga);
          }
        }
      }
    } finally {
      _isDraining = false;
      if (_pending.isNotEmpty) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 120), _drainQueue);
      }
    }
  }

  Future<void> _fetchBatch(
    List<_BannerLookupTask> batch, {
    required bool isMal,
    required bool isManga,
  }) async {
    if (batch.isEmpty) return;

    for (final t in batch) {
      _inFlightKeys.add(t.cacheKey);
    }

    final ids = batch.map((e) => e.id).toList();
    final mediaType = isManga ? 'MANGA' : 'ANIME';
    final query = isMal
        ? r'''
          query ($ids: [Int], $type: MediaType) {
            Page(page: 1, perPage: 50) {
              media(idMal_in: $ids, type: $type) {
                id
                idMal
                bannerImage
              }
            }
          }
        '''
        : r'''
          query ($ids: [Int], $type: MediaType) {
            Page(page: 1, perPage: 50) {
              media(id_in: $ids, type: $type) {
                id
                idMal
                bannerImage
              }
            }
          }
        ''';

    final token = AuthKeys.authToken.get<String?>();
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null && token.trim().isNotEmpty)
        'Authorization': 'Bearer ${token.trim()}',
    };

    try {
      await AnilistRateLimiter.instance.acquire();
      final response = await _client.post(
        Uri.parse(_endpoint),
        headers: headers,
        body: json.encode({
          'query': query,
          'variables': {'ids': ids, 'type': mediaType},
        }),
      );
      AnilistRateLimiter.instance.onResponse(
        statusCode: response.statusCode,
        headers: response.headers,
      );

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        final mediaList =
            decoded?['data']?['Page']?['media'] as List<dynamic>? ?? const [];

        final matchedIds = <int>{};
        bool updated = false;

        for (final item in mediaList) {
          if (item is! Map) continue;
          final alId = (item['id'] as num?)?.toInt();
          final malId = (item['idMal'] as num?)?.toInt();
          final banner = item['bannerImage']?.toString();
          final validBanner =
              (banner != null && banner.trim().isNotEmpty) ? banner.trim() : null;

          if (alId != null && alId > 0) {
            final k = 'al:$mediaType:$alId';
            if (_cache[k] != validBanner) {
              _cache[k] = validBanner;
              if (validBanner != null) updated = true;
            }
            if (!isMal) matchedIds.add(alId);
          }
          if (malId != null && malId > 0) {
            final k = 'mal:$mediaType:$malId';
            if (_cache[k] != validBanner) {
              _cache[k] = validBanner;
              if (validBanner != null) updated = true;
            }
            if (isMal) matchedIds.add(malId);
          }
        }

        // Mark unresolved IDs as null so we don't keep re-fetching them
        for (final t in batch) {
          if (!matchedIds.contains(t.id) && !_cache.containsKey(t.cacheKey)) {
            _cache[t.cacheKey] = null;
          }
        }

        if (updated) {
          _persistToDisk();
          version.value++;
        }
      } else {
        Logger.i('AnilistBannerResolver HTTP ${response.statusCode}');
      }
    } catch (e) {
      Logger.i('AnilistBannerResolver batch error: $e');
    } finally {
      for (final t in batch) {
        _inFlightKeys.remove(t.cacheKey);
      }
    }
  }
}
