import 'package:anymex/controllers/service_handler/service_handler.dart';
import 'package:anymex/controllers/services/anilist/anilist_banner_resolver.dart';

class CarouselData {
  String? id;
  String? title;
  String? romajiTitle;
  String? englishTitle;
  String? poster;
  String? cover;
  String? extraData;
  String? source;
  String? args;
  ServicesType servicesType;
  bool releasing;

  int? anilistUserId;
  int? malUserId;
  String? author;
  String? reason;

  CarouselData({
    this.id,
    this.title,
    this.romajiTitle,
    this.englishTitle,
    this.poster,
    this.cover,
    this.extraData,
    this.source,
    this.args,
    required this.servicesType,
    required this.releasing,
    this.anilistUserId,
    this.malUserId,
    this.author,
    this.reason,
  });

  static bool isValidImageUrl(String? url) {
    if (url == null) return false;
    final trimmed = url.trim();
    return trimmed.isNotEmpty &&
        trimmed != '?' &&
        trimmed != '??' &&
        trimmed != 'null';
  }

  String? resolvedLandscapeCover({
    bool isManga = false,
    bool scheduleFetch = true,
  }) {
    if (AnilistBannerResolver.isLandscapeBannerUrl(cover, poster: poster)) {
      return cover!.trim();
    }
    final resolved = scheduleFetch
        ? AnilistBannerResolver.instance.lookupOrSchedule(
            id: id,
            serviceType: servicesType,
            isManga: isManga,
          )
        : AnilistBannerResolver.instance.getCached(
            id: id,
            serviceType: servicesType,
            isManga: isManga,
          );
    if (isValidImageUrl(resolved)) {
      return resolved!.trim();
    }
    return null;
  }

  bool usesCover({required bool isLandscape, bool isManga = false}) {
    if (!isLandscape) return false;
    return resolvedLandscapeCover(isManga: isManga, scheduleFetch: false) !=
        null;
  }

  String imageFor({required bool isLandscape, bool isManga = false}) {
    if (isLandscape) {
      final resolved = resolvedLandscapeCover(
        isManga: isManga,
        scheduleFetch: true,
      );
      if (resolved != null) {
        return resolved;
      }
    }
    return poster ?? '';
  }

  String? fallbackImageFor({required bool isLandscape, bool isManga = false}) {
    if (!isLandscape) return null;
    final resolved = resolvedLandscapeCover(
      isManga: isManga,
      scheduleFetch: false,
    );
    if (resolved != null && isValidImageUrl(poster) && resolved != poster) {
      return poster;
    }
    return null;
  }
}
