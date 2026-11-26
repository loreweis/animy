class AnilistThreadCategory {
  final int id;
  final String name;

  const AnilistThreadCategory({
    required this.id,
    required this.name,
  });

  factory AnilistThreadCategory.fromJson(Map<String, dynamic> json) {
    return AnilistThreadCategory(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? '',
    );
  }
}

class AnilistThreadUser {
  final int id;
  final String name;
  final String? avatarUrl;

  const AnilistThreadUser({
    required this.id,
    required this.name,
    this.avatarUrl,
  });

  factory AnilistThreadUser.fromJson(Map<String, dynamic> json) {
    final avatar = json['avatar'];
    String? avatarUrl;
    if (avatar is Map) {
      avatarUrl = avatar['large']?.toString() ?? avatar['medium']?.toString();
    }
    return AnilistThreadUser(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? 'Unknown',
      avatarUrl: avatarUrl,
    );
  }
}

class AnilistThread {
  final int id;
  final String title;
  final String bodyHtml;
  final int userId;
  final int replyCount;
  final int viewCount;
  final int likeCount;
  final bool isLiked;
  final bool isLocked;
  final bool isSticky;
  final bool isSubscribed;
  final int createdAt;
  final int? repliedAt;
  final int updatedAt;
  final String? siteUrl;
  final AnilistThreadUser? user;
  final AnilistThreadUser? replyUser;
  final List<AnilistThreadCategory> categories;

  const AnilistThread({
    required this.id,
    required this.title,
    required this.bodyHtml,
    required this.userId,
    required this.replyCount,
    required this.viewCount,
    required this.likeCount,
    required this.isLiked,
    required this.isLocked,
    required this.isSticky,
    required this.isSubscribed,
    required this.createdAt,
    this.repliedAt,
    required this.updatedAt,
    this.siteUrl,
    this.user,
    this.replyUser,
    this.categories = const [],
  });

  AnilistThread copyWith({
    String? title,
    String? bodyHtml,
    int? replyCount,
    int? viewCount,
    int? likeCount,
    bool? isLiked,
    bool? isLocked,
    bool? isSticky,
    bool? isSubscribed,
    int? repliedAt,
    int? updatedAt,
    AnilistThreadUser? replyUser,
  }) {
    return AnilistThread(
      id: id,
      title: title ?? this.title,
      bodyHtml: bodyHtml ?? this.bodyHtml,
      userId: userId,
      replyCount: replyCount ?? this.replyCount,
      viewCount: viewCount ?? this.viewCount,
      likeCount: likeCount ?? this.likeCount,
      isLiked: isLiked ?? this.isLiked,
      isLocked: isLocked ?? this.isLocked,
      isSticky: isSticky ?? this.isSticky,
      isSubscribed: isSubscribed ?? this.isSubscribed,
      createdAt: createdAt,
      repliedAt: repliedAt ?? this.repliedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      siteUrl: siteUrl,
      user: user,
      replyUser: replyUser ?? this.replyUser,
      categories: categories,
    );
  }

  factory AnilistThread.fromJson(Map<String, dynamic> json) {
    final rawCategories = json['categories'] as List<dynamic>? ?? const [];
    return AnilistThread(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: json['title']?.toString() ?? 'Untitled Thread',
      bodyHtml: json['body']?.toString() ?? '',
      userId: (json['userId'] as num?)?.toInt() ?? 0,
      replyCount: (json['replyCount'] as num?)?.toInt() ?? 0,
      viewCount: (json['viewCount'] as num?)?.toInt() ?? 0,
      likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
      isLiked: json['isLiked'] == true,
      isLocked: json['isLocked'] == true,
      isSticky: json['isSticky'] == true,
      isSubscribed: json['isSubscribed'] == true,
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      repliedAt: (json['repliedAt'] as num?)?.toInt(),
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
      siteUrl: json['siteUrl']?.toString(),
      user: json['user'] is Map
          ? AnilistThreadUser.fromJson(
              Map<String, dynamic>.from(json['user'] as Map),
            )
          : null,
      replyUser: json['replyUser'] is Map
          ? AnilistThreadUser.fromJson(
              Map<String, dynamic>.from(json['replyUser'] as Map),
            )
          : null,
      categories: rawCategories
          .whereType<Map>()
          .map((e) =>
              AnilistThreadCategory.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

class AnilistThreadComment {
  final int id;
  final int threadId;
  final int userId;
  final String commentHtml;
  final int likeCount;
  final bool isLiked;
  final bool isLocked;
  final int createdAt;
  final int updatedAt;
  final AnilistThreadUser? user;
  final List<AnilistThreadComment> childComments;

  const AnilistThreadComment({
    required this.id,
    required this.threadId,
    required this.userId,
    required this.commentHtml,
    required this.likeCount,
    required this.isLiked,
    required this.isLocked,
    required this.createdAt,
    required this.updatedAt,
    this.user,
    this.childComments = const [],
  });

  AnilistThreadComment copyWith({
    String? commentHtml,
    int? likeCount,
    bool? isLiked,
    bool? isLocked,
    int? updatedAt,
    List<AnilistThreadComment>? childComments,
  }) {
    return AnilistThreadComment(
      id: id,
      threadId: threadId,
      userId: userId,
      commentHtml: commentHtml ?? this.commentHtml,
      likeCount: likeCount ?? this.likeCount,
      isLiked: isLiked ?? this.isLiked,
      isLocked: isLocked ?? this.isLocked,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      user: user,
      childComments: childComments ?? this.childComments,
    );
  }

  factory AnilistThreadComment.fromJson(
    Map<String, dynamic> json, {
    int fallbackThreadId = 0,
  }) {
    final resolvedThreadId =
        (json['threadId'] as num?)?.toInt() ?? fallbackThreadId;
    final rawChildren = json['childComments'];
    final children = <AnilistThreadComment>[];
    if (rawChildren is List) {
      for (final item in rawChildren) {
        if (item is Map) {
          children.add(
            AnilistThreadComment.fromJson(
              Map<String, dynamic>.from(item),
              fallbackThreadId: resolvedThreadId,
            ),
          );
        }
      }
    }
    final userMap = json['user'];
    final parsedUser = userMap is Map
        ? AnilistThreadUser.fromJson(Map<String, dynamic>.from(userMap))
        : null;
    return AnilistThreadComment(
      id: (json['id'] as num?)?.toInt() ?? 0,
      threadId: resolvedThreadId,
      userId: (json['userId'] as num?)?.toInt() ?? parsedUser?.id ?? 0,
      commentHtml: json['comment']?.toString() ?? '',
      likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
      isLiked: json['isLiked'] == true,
      isLocked: json['isLocked'] == true,
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
      user: parsedUser,
      childComments: children,
    );
  }
}
