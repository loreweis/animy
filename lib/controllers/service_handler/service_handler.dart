import 'package:anymex/controllers/cacher/cache_controller.dart';
import 'package:anymex/controllers/settings/settings.dart';
import 'package:anymex/controllers/service_handler/params.dart';
import 'package:anymex/controllers/services/anilist/anilist_data.dart';
import 'package:anymex/controllers/services/mal/mal_service.dart';
import 'package:anymex/controllers/services/simkl/simkl_service.dart';
import 'package:anymex/controllers/source/source_controller.dart';
import 'package:anymex/database/data_keys/keys.dart';
import 'package:anymex/models/Anilist/anilist_media_user.dart';
import 'package:anymex/models/Anilist/anilist_profile.dart';
import 'package:anymex/models/Media/media.dart';
import 'package:anymex/models/Service/base_service.dart';
import 'package:anymex/models/Service/online_service.dart';
import 'package:anymex/utils/logger.dart';
import 'package:anymex_extension_runtime_bridge/Models/Source.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

enum ServicesType {
  anilist,
  mal,
  simkl,
  extensions;

  bool get isMal => this == ServicesType.mal;
  bool get isAL => this == ServicesType.anilist;
  bool get isSimkl => this == ServicesType.simkl;

  BaseService get service {
    switch (this) {
      case ServicesType.anilist:
        return Get.find<AnilistData>();
      case ServicesType.mal:
        return Get.find<MalService>();
      case ServicesType.simkl:
        return Get.find<SimklService>();
      case ServicesType.extensions:
        return Get.find<SourceController>();
    }
  }

  OnlineService get onlineService {
    switch (this) {
      case ServicesType.anilist:
        return Get.find<AnilistData>();
      case ServicesType.mal:
        return Get.find<MalService>();
      case ServicesType.simkl:
        return Get.find<SimklService>();
      default:
        return Get.find<AnilistData>();
    }
  }
}

final serviceHandler = Get.find<ServiceHandler>();

class ServiceHandler extends GetxController {
  final serviceType = ServicesType.anilist.obs;
  final anilistService = Get.find<AnilistData>();
  final malService = Get.find<MalService>();
  final simklService = Get.find<SimklService>();
  final extensionService = Get.find<SourceController>();
  final isHomeLoading = true.obs;
  final isAutoLoggingIn = false.obs;

  bool get hasSavedTokenForActiveService {
    switch (serviceType.value) {
      case ServicesType.anilist:
        final token = AuthKeys.authToken.get<String?>();
        return token != null && token.isNotEmpty;
      case ServicesType.mal:
        final token = AuthKeys.malAuthToken.get<String?>();
        final refresh = AuthKeys.malRefreshToken.get<String?>();
        return (token != null && token.isNotEmpty) ||
            (refresh != null && refresh.isNotEmpty);
      case ServicesType.simkl:
        final token = AuthKeys.simklAuthToken.get<String?>();
        return token != null && token.isNotEmpty;
      case ServicesType.extensions:
        return false;
    }
  }

  BaseService get service {
    switch (serviceType.value) {
      case ServicesType.anilist:
        return anilistService;
      case ServicesType.mal:
        return malService;
      case ServicesType.simkl:
        return simklService;
      case ServicesType.extensions:
        return extensionService;
    }
  }

  OnlineService get onlineService {
    switch (serviceType.value) {
      case ServicesType.anilist:
        return anilistService;
      case ServicesType.mal:
        return malService;
      case ServicesType.simkl:
        return simklService;
      default:
        return anilistService;
    }
  }

  OnlineService? get activeOrLoggedInOnlineService {
    if (serviceType.value == ServicesType.extensions) {
      if (anilistService.isLoggedIn.value) return anilistService;
      if (malService.isLoggedIn.value) return malService;
      if (simklService.isLoggedIn.value) return simklService;
      return null;
    }
    return onlineService;
  }

  Rx<Profile> get profileData {
    if (serviceType.value == ServicesType.extensions) {
      final activeService = activeOrLoggedInOnlineService;
      if (activeService != null) {
        return activeService.profileData;
      }
      return Profile(name: 'Guest').obs;
    }
    return onlineService.profileData;
  }

  RxList<TrackedMedia> get animeList => onlineService.animeList;
  RxList<TrackedMedia> get mangaList => onlineService.mangaList;

  Rx<TrackedMedia> get currentMedia => onlineService.currentMedia;

  RxBool get isLoggedIn {
    if (serviceType.value == ServicesType.extensions) {
      return (activeOrLoggedInOnlineService != null).obs;
    }
    return onlineService.isLoggedIn;
  }

  // Online Services Method
  Future<void> login(BuildContext context) => onlineService.login(context);
  Future<void> logout() => onlineService.logout();
  Future<void> _runServiceAutoLogin(
    ServicesType type,
    Future<void> Function() task,
  ) async {
    try {
      await task();
    } catch (e) {
      Logger.i('${type.name} autoLogin error: $e');
    } finally {
      if (serviceType.value == type) {
        isAutoLoggingIn.value = false;
      }
    }
  }

  Future<void> autoLogin() async {
    isAutoLoggingIn.value = hasSavedTokenForActiveService;
    try {
      await Future.wait([
        _runServiceAutoLogin(ServicesType.mal, malService.autoLogin),
        _runServiceAutoLogin(ServicesType.anilist, anilistService.autoLogin),
        _runServiceAutoLogin(ServicesType.simkl, simklService.autoLogin),
      ]);
    } finally {
      isAutoLoggingIn.value = false;
    }
  }
  @override
  Future<void> refresh() => onlineService.refresh();

  Future<void> updateListEntry(
    UpdateListEntryParams params,
  ) async {
    if (Get.isRegistered<Settings>() &&
        Get.find<Settings>().isIncognito.value) {
      return;
    }
    await onlineService.updateListEntry(params);
  }

  RxList<Widget> animeWidgets(BuildContext context) =>
      service.animeWidgets(context);
  RxList<Widget> mangaWidgets(BuildContext context) =>
      service.mangaWidgets(context);
  RxList<Widget> homeWidgets(BuildContext context) =>
      service.homeWidgets(context);

  RxList<Widget> novelWidgets(BuildContext context) =>
      service.novelWidgets(context);

  Source? getSourceForMedia(Media media) {
    if (media.serviceType == ServicesType.extensions) {
      return extensionService.installedNovelExtensions.firstWhere(
        (source) => source.name == media.sourceName,
        orElse: () => extensionService.installedNovelExtensions.first,
      );
    }
    return null;
  }

  @override
  void onInit() {
    super.onInit();
    serviceType.value =
        ServicesType.values[ServiceKeys.serviceType.get<int>(0)];
    isAutoLoggingIn.value = hasSavedTokenForActiveService;
    isHomeLoading.value = serviceType.value != ServicesType.extensions;
  }

  @override
  void onReady() {
    super.onReady();
    fetchHomePage();
    autoLogin();
  }

  Future<void> fetchHomePage() async {
    isHomeLoading.value = true;
    try {
      await service.fetchHomePage();
    } catch (e) {
      Logger.i('Home fetch error: $e');
    } finally {
      isHomeLoading.value = false;
    }
  }

  Future<Media> fetchDetails(FetchDetailsParams params) async {
    try {
      if (serviceType.value == ServicesType.extensions) {
        return await service.fetchDetails(params);
      }
      Media? data = cacheController.getCacheById(params.id, serviceType.value);
      return await (data ?? service.fetchDetails(params));
    } catch (e) {
      Logger.i("Cache Error => $e");
      return service.fetchDetails(params);
    }
  }

  Future<List<Media>?> search(SearchParams params) async =>
      service.search(params);

  void clearState() => service.clearState();

  void changeService(ServicesType type) {
    ServiceKeys.serviceType.set(type.index);
    serviceType.value = type;
    if (!service.isDataLoaded) {
      fetchHomePage();
    }
  }
}
