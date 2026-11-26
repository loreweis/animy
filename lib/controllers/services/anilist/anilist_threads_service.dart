import 'dart:convert';

import 'package:anymex/controllers/network/network_manager.dart';
import 'package:anymex/controllers/service_handler/service_handler.dart';
import 'package:anymex/controllers/services/anilist/anilist_rate_limiter.dart';
import 'package:anymex/database/data_keys/keys.dart';
import 'package:anymex/models/Anilist/anilist_thread.dart';
import 'package:anymex/models/Media/media.dart';
import 'package:anymex/utils/logger.dart';
import 'package:anymex_extension_runtime_bridge/Models/Source.dart';
import 'package:http/http.dart' as http;

class AnilistThreadsService {
  static const String _endpoint = 'https://graphql.anilist.co';
  static final Map<String, int?> _resolvedMediaIdCache = {};

  static http.Client get _client => NetworkManager.instance.compatibleClient;

  static String? get _token {
    final token = AuthKeys.authToken.get<String?>();
    if (token == null || token.trim().isEmpty) return null;
    return token.trim();
  }

  static bool get hasAnilistToken => _token != null;

  static Future<Map<String, dynamic>?> _post({
    required String query,
    Map<String, dynamic>? variables,
    bool requireAuth = false,
  }) async {
    final token = _token;
    if (requireAuth && token == null) return null;

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    try {
      await AnilistRateLimiter.instance.acquire();
      final response = await _client.post(
        Uri.parse(_endpoint),
        headers: headers,
        body: json.encode({
          'query': query,
          if (variables != null) 'variables': variables,
        }),
      );
      AnilistRateLimiter.instance.onResponse(
        statusCode: response.statusCode,
        headers: response.headers,
      );

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      } else {
        Logger.i(
          'AniList Threads HTTP ${response.statusCode}: ${response.body}',
        );
      }
    } catch (e) {
      Logger.e('AniList Threads request error: $e');
    }
    return null;
  }

  static Future<int?> resolveAnilistMediaId(Media media) async {
    if (media.serviceType == ServicesType.anilist) {
      final parsed = int.tryParse(media.id);
      if (parsed != null && parsed > 0) return parsed;
    }

    final cacheKey =
        '${media.serviceType.name}:${media.id}:${media.idMal}:${media.mediaType.name}';
    if (_resolvedMediaIdCache.containsKey(cacheKey)) {
      return _resolvedMediaIdCache[cacheKey];
    }

    final isManga = media.mediaType != ItemType.anime;
    final mediaTypeStr = isManga ? 'MANGA' : 'ANIME';

    int? malId = int.tryParse(media.idMal);
    if ((malId == null || malId <= 0) &&
        media.serviceType == ServicesType.mal) {
      malId = int.tryParse(media.id);
    }

    if (malId != null && malId > 0) {
      const malQuery = r'''
        query ($idMal: Int, $type: MediaType) {
          Media(idMal: $idMal, type: $type) {
            id
          }
        }
      ''';
      final data = await _post(
        query: malQuery,
        variables: {'idMal': malId, 'type': mediaTypeStr},
      );
      final id = (data?['data']?['Media']?['id'] as num?)?.toInt();
      if (id != null && id > 0) {
        _resolvedMediaIdCache[cacheKey] = id;
        return id;
      }
    }

    final searchTitle = (media.romajiTitle.isNotEmpty &&
            media.romajiTitle != '?' &&
            media.romajiTitle != '??')
        ? media.romajiTitle
        : media.title;
    if (searchTitle.trim().isNotEmpty &&
        searchTitle != '?' &&
        searchTitle != '??') {
      const searchQuery = r'''
        query ($search: String, $type: MediaType) {
          Media(search: $search, type: $type) {
            id
          }
        }
      ''';
      final data = await _post(
        query: searchQuery,
        variables: {'search': searchTitle.trim(), 'type': mediaTypeStr},
      );
      final id = (data?['data']?['Media']?['id'] as num?)?.toInt();
      _resolvedMediaIdCache[cacheKey] = id;
      return id;
    }

    _resolvedMediaIdCache[cacheKey] = null;
    return null;
  }

  static Future<(List<AnilistThread>, bool)> fetchMediaThreads({
    required int mediaId,
    int page = 1,
    int perPage = 20,
    List<String> sort = const ['IS_STICKY', 'REPLIED_AT_DESC'],
    String? search,
  }) async {
    const query = r'''
      query ($mediaId: Int, $page: Int, $perPage: Int, $sort: [ThreadSort], $search: String) {
        Page(page: $page, perPage: $perPage) {
          pageInfo {
            currentPage
            lastPage
            hasNextPage
          }
          threads(mediaCategoryId: $mediaId, sort: $sort, search: $search) {
            id
            title
            body(asHtml: true)
            userId
            replyCount
            viewCount
            isLocked
            isSticky
            isSubscribed
            likeCount
            isLiked
            repliedAt
            createdAt
            updatedAt
            siteUrl
            user {
              id
              name
              avatar {
                large
                medium
              }
            }
            replyUser {
              id
              name
              avatar {
                large
                medium
              }
            }
            categories {
              id
              name
            }
          }
        }
      }
    ''';

    final cleanSearch = search?.trim();
    final variables = <String, dynamic>{
      'mediaId': mediaId,
      'page': page,
      'perPage': perPage,
      'sort': sort,
      if (cleanSearch != null && cleanSearch.isNotEmpty) 'search': cleanSearch,
    };

    final data = await _post(query: query, variables: variables);
    final pageObj = data?['data']?['Page'] as Map<String, dynamic>?;
    if (pageObj == null) {
      return (<AnilistThread>[], false);
    }

    final rawList = pageObj['threads'] as List<dynamic>? ?? const [];
    final threads = rawList
        .whereType<Map>()
        .map((e) => AnilistThread.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final hasNext = pageObj['pageInfo']?['hasNextPage'] == true;
    return (threads, hasNext);
  }

  static Future<AnilistThread?> fetchThreadDetail(int threadId) async {
    const query = r'''
      query ($id: Int) {
        Thread(id: $id) {
          id
          title
          body(asHtml: true)
          userId
          replyCount
          viewCount
          isLocked
          isSticky
          isSubscribed
          likeCount
          isLiked
          repliedAt
          createdAt
          updatedAt
          siteUrl
          user {
            id
            name
            avatar {
              large
              medium
            }
          }
          replyUser {
            id
            name
            avatar {
              large
              medium
            }
          }
          categories {
            id
            name
          }
        }
      }
    ''';

    final data = await _post(query: query, variables: {'id': threadId});
    final threadMap = data?['data']?['Thread'];
    if (threadMap is Map) {
      return AnilistThread.fromJson(Map<String, dynamic>.from(threadMap));
    }
    return null;
  }

  static Future<(List<AnilistThreadComment>, bool)> fetchThreadComments({
    required int threadId,
    int page = 1,
    int perPage = 25,
    String sort = 'ID',
  }) async {
    const query = r'''
      query ($threadId: Int, $page: Int, $perPage: Int, $sort: [ThreadCommentSort]) {
        Page(page: $page, perPage: $perPage) {
          pageInfo {
            currentPage
            lastPage
            hasNextPage
          }
          threadComments(threadId: $threadId, sort: $sort) {
            id
            userId
            threadId
            comment(asHtml: true)
            likeCount
            isLiked
            isLocked
            createdAt
            updatedAt
            user {
              id
              name
              avatar {
                large
                medium
              }
            }
            childComments
          }
        }
      }
    ''';

    final data = await _post(
      query: query,
      variables: {
        'threadId': threadId,
        'page': page,
        'perPage': perPage,
        'sort': [sort],
      },
    );

    final pageObj = data?['data']?['Page'] as Map<String, dynamic>?;
    if (pageObj == null) {
      return (<AnilistThreadComment>[], false);
    }

    final rawList = pageObj['threadComments'] as List<dynamic>? ?? const [];
    final comments = rawList
        .whereType<Map>()
        .map(
          (e) => AnilistThreadComment.fromJson(
            Map<String, dynamic>.from(e),
            fallbackThreadId: threadId,
          ),
        )
        .toList();
    final hasNext = pageObj['pageInfo']?['hasNextPage'] == true;
    return (comments, hasNext);
  }

  static Future<({int likeCount, bool isLiked})?> toggleThreadLike(
    int threadId,
  ) async {
    const mutation = r'''
      mutation ($id: Int) {
        ToggleLikeV2(id: $id, type: THREAD) {
          ... on Thread {
            likeCount
            isLiked
          }
        }
      }
    ''';

    final data = await _post(
      query: mutation,
      variables: {'id': threadId},
      requireAuth: true,
    );
    final res = data?['data']?['ToggleLikeV2'];
    if (res is Map) {
      return (
        likeCount: (res['likeCount'] as num?)?.toInt() ?? 0,
        isLiked: res['isLiked'] == true,
      );
    }
    return null;
  }

  static Future<({int likeCount, bool isLiked})?> toggleThreadCommentLike(
    int commentId,
  ) async {
    const mutation = r'''
      mutation ($id: Int) {
        ToggleLikeV2(id: $id, type: THREAD_COMMENT) {
          ... on ThreadComment {
            likeCount
            isLiked
          }
        }
      }
    ''';

    final data = await _post(
      query: mutation,
      variables: {'id': commentId},
      requireAuth: true,
    );
    final res = data?['data']?['ToggleLikeV2'];
    if (res is Map) {
      return (
        likeCount: (res['likeCount'] as num?)?.toInt() ?? 0,
        isLiked: res['isLiked'] == true,
      );
    }
    return null;
  }

  static Future<bool?> toggleThreadSubscription(
    int threadId,
    bool subscribe,
  ) async {
    const mutation = r'''
      mutation ($threadId: Int, $subscribe: Boolean) {
        ToggleThreadSubscription(threadId: $threadId, subscribe: $subscribe) {
          id
          isSubscribed
        }
      }
    ''';

    final data = await _post(
      query: mutation,
      variables: {'threadId': threadId, 'subscribe': subscribe},
      requireAuth: true,
    );
    final res = data?['data']?['ToggleThreadSubscription'];
    if (res is Map) {
      return res['isSubscribed'] == true;
    }
    return null;
  }

  static Future<AnilistThreadComment?> saveThreadComment({
    required int threadId,
    required String comment,
    int? parentCommentId,
    int? id,
  }) async {
    const mutation = r'''
      mutation ($id: Int, $threadId: Int, $parentCommentId: Int, $comment: String) {
        SaveThreadComment(
          id: $id
          threadId: $threadId
          parentCommentId: $parentCommentId
          comment: $comment
        ) {
          id
          userId
          threadId
          comment(asHtml: true)
          likeCount
          isLiked
          isLocked
          createdAt
          updatedAt
          user {
            id
            name
            avatar {
              large
              medium
            }
          }
          childComments
        }
      }
    ''';

    final data = await _post(
      query: mutation,
      variables: {
        if (id != null) 'id': id,
        'threadId': threadId,
        if (parentCommentId != null) 'parentCommentId': parentCommentId,
        'comment': comment,
      },
      requireAuth: true,
    );
    final res = data?['data']?['SaveThreadComment'];
    if (res is Map) {
      return AnilistThreadComment.fromJson(
        Map<String, dynamic>.from(res),
        fallbackThreadId: threadId,
      );
    }
    return null;
  }

  static Future<bool> deleteThreadComment(int commentId) async {
    const mutation = r'''
      mutation ($id: Int) {
        DeleteThreadComment(id: $id) {
          deleted
        }
      }
    ''';

    final data = await _post(
      query: mutation,
      variables: {'id': commentId},
      requireAuth: true,
    );
    return data?['data']?['DeleteThreadComment']?['deleted'] == true;
  }

  static Future<AnilistThread?> saveThread({
    required String title,
    required String body,
    required int mediaId,
    required bool isManga,
  }) async {
    const mutation = r'''
      mutation ($title: String, $body: String, $categories: [Int], $mediaCategories: [Int]) {
        SaveThread(
          title: $title
          body: $body
          categories: $categories
          mediaCategories: $mediaCategories
        ) {
          id
          title
          body(asHtml: true)
          userId
          replyCount
          viewCount
          isLocked
          isSticky
          isSubscribed
          likeCount
          isLiked
          repliedAt
          createdAt
          updatedAt
          siteUrl
          user {
            id
            name
            avatar {
              large
              medium
            }
          }
          replyUser {
            id
            name
            avatar {
              large
              medium
            }
          }
          categories {
            id
            name
          }
        }
      }
    ''';

    final data = await _post(
      query: mutation,
      variables: {
        'title': title.trim(),
        'body': body.trim(),
        'categories': [isManga ? 2 : 1],
        'mediaCategories': [mediaId],
      },
      requireAuth: true,
    );
    final res = data?['data']?['SaveThread'];
    if (res is Map) {
      return AnilistThread.fromJson(Map<String, dynamic>.from(res));
    }
    return null;
  }
}
