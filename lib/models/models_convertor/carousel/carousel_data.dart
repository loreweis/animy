import 'package:anymex/controllers/service_handler/service_handler.dart';

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

  static bool _isValidImageUrl(String? url) {
    if (url == null) return false;
    final trimmed = url.trim();
    return trimmed.isNotEmpty &&
        trimmed != '?' &&
        trimmed != '??' &&
        trimmed != 'null';
  }

  String imageFor({required bool isLandscape}) {
    if (isLandscape && _isValidImageUrl(cover)) {
      return cover!;
    }
    return poster ?? '';
  }

  String? fallbackImageFor({required bool isLandscape}) {
    if (isLandscape &&
        _isValidImageUrl(cover) &&
        _isValidImageUrl(poster) &&
        cover != poster) {
      return poster;
    }
    return null;
  }
}
