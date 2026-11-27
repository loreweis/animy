import 'dart:ui';

import 'package:anymex/controllers/services/anilist/anilist_auth.dart';
import 'package:anymex/controllers/services/anilist/anilist_threads_service.dart';
import 'package:anymex/controllers/settings/settings.dart';
import 'package:anymex/database/data_keys/keys.dart';
import 'package:anymex/models/Anilist/anilist_thread.dart';
import 'package:anymex/models/Media/media.dart';
import 'package:anymex/screens/anime/widgets/threads/anilist_thread_composer.dart';
import 'package:anymex/screens/profile/user_profile_page.dart';
import 'package:anymex/utils/al_about_me.dart';
import 'package:anymex/utils/function.dart';
import 'package:anymex/utils/theme_extensions.dart';
import 'package:anymex/widgets/anymex_widgets/anymex_image.dart';
import 'package:anymex/widgets/anymex_widgets/anymex_text.dart';
import 'package:anymex/widgets/common/anymex_scaffold.dart';
import 'package:anymex/widgets/common/baked_blur_image.dart';
import 'package:anymex/widgets/non_widgets/snackbar.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

class AnilistThreadDetailPage extends StatefulWidget {
  final AnilistThread initialThread;
  final Media? media;
  final String posterColorHex;
  final ValueChanged<AnilistThread>? onThreadUpdated;
  final ThemeData? inheritedTheme;

  const AnilistThreadDetailPage({
    super.key,
    required this.initialThread,
    this.media,
    this.posterColorHex = '',
    this.onThreadUpdated,
    this.inheritedTheme,
  });

  @override
  State<AnilistThreadDetailPage> createState() =>
      _AnilistThreadDetailPageState();
}

class _AnilistThreadDetailPageState extends State<AnilistThreadDetailPage> {
  late AnilistThread _thread;
  List<AnilistThreadComment> _comments = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasNextPage = false;
  int _currentPage = 1;
  String _commentSort = 'ID'; // 'ID' = Oldest, 'ID_DESC' = Newest

  final TextEditingController _replyController = TextEditingController();
  final FocusNode _composerFocusNode = FocusNode();
  final ValueNotifier<AnilistThreadComment?> _replyingToNotifier =
      ValueNotifier<AnilistThreadComment?>(null);

  /// Comments whose nested replies are currently expanded.
  /// Collapsed by default so expand indicator (⌄ N) is immediately clear
  /// and fewer HtmlWidgets are mounted upfront.
  final Set<int> _expandedCommentIds = {};

  int? get _currentUserId {
    if (!Get.isRegistered<AnilistAuth>()) return null;
    final auth = Get.find<AnilistAuth>();
    final idStr = auth.profileData.value.id;
    return idStr != null ? int.tryParse(idStr) : null;
  }

  @override
  void initState() {
    super.initState();
    _thread = widget.initialThread;
    _loadInitial();
  }

  @override
  void dispose() {
    _replyController.dispose();
    _composerFocusNode.dispose();
    _replyingToNotifier.dispose();
    super.dispose();
  }

  bool get _isNewestSort => _commentSort == 'ID_DESC';

  Future<void> _loadInitial({bool refreshThread = true}) async {
    setState(() {
      _isLoading = true;
      _currentPage = 1;
    });

    AnilistThread? fetchedThread;
    if (refreshThread) {
      fetchedThread = await AnilistThreadsService.fetchThreadDetail(_thread.id);
      if (!mounted) return;
      if (fetchedThread != null) {
        _thread = fetchedThread;
        widget.onThreadUpdated?.call(_thread);
      }
    }

    // Fetch page 1 first (no `sort` param so AniList preserves `childComments`)
    final (page1Comments, page1HasNext, lastPage) =
        await AnilistThreadsService.fetchThreadComments(
      threadId: _thread.id,
      page: 1,
    );
    if (!mounted) return;

    if (!_isNewestSort) {
      setState(() {
        _currentPage = 1;
        _comments = page1Comments;
        _hasNextPage = page1HasNext;
        _isLoading = false;
      });
      return;
    }

    // Newest first: jump to lastPage and reverse order while keeping childComments intact
    if (lastPage <= 1) {
      setState(() {
        _currentPage = 1;
        _comments = page1Comments.reversed.toList();
        _hasNextPage = false;
        _isLoading = false;
      });
      return;
    }

    final (lastComments, _, _) =
        await AnilistThreadsService.fetchThreadComments(
      threadId: _thread.id,
      page: lastPage,
    );
    if (!mounted) return;

    setState(() {
      _currentPage = lastPage;
      _comments = lastComments.reversed.toList();
      _hasNextPage = lastPage > 1;
      _isLoading = false;
    });
  }

  Future<void> _loadMoreComments() async {
    if (_isLoadingMore || !_hasNextPage) return;
    setState(() => _isLoadingMore = true);

    if (!_isNewestSort) {
      final nextPage = _currentPage + 1;
      final (more, hasNext, _) =
          await AnilistThreadsService.fetchThreadComments(
        threadId: _thread.id,
        page: nextPage,
      );
      if (!mounted) return;
      setState(() {
        _currentPage = nextPage;
        _comments = [..._comments, ...more];
        _hasNextPage = hasNext;
        _isLoadingMore = false;
      });
    } else {
      final prevPage = _currentPage - 1;
      if (prevPage < 1) {
        setState(() {
          _hasNextPage = false;
          _isLoadingMore = false;
        });
        return;
      }
      final (more, _, _) = await AnilistThreadsService.fetchThreadComments(
        threadId: _thread.id,
        page: prevPage,
      );
      if (!mounted) return;
      setState(() {
        _currentPage = prevPage;
        _comments = [..._comments, ...more.reversed];
        _hasNextPage = prevPage > 1;
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _toggleThreadLike() async {
    if (!AnilistThreadsService.hasAnilistToken) {
      snackBar('Log in to AniList to like threads');
      return;
    }
    final prev = _thread;
    final optimistic = _thread.copyWith(
      isLiked: !_thread.isLiked,
      likeCount: _thread.isLiked
          ? (_thread.likeCount - 1).clamp(0, 1 << 30)
          : _thread.likeCount + 1,
    );
    setState(() => _thread = optimistic);
    widget.onThreadUpdated?.call(_thread);

    final res = await AnilistThreadsService.toggleThreadLike(_thread.id);
    if (!mounted) return;
    if (res != null) {
      setState(() {
        _thread = _thread.copyWith(
          likeCount: res.likeCount,
          isLiked: res.isLiked,
        );
      });
      widget.onThreadUpdated?.call(_thread);
    } else {
      setState(() => _thread = prev);
      widget.onThreadUpdated?.call(_thread);
      errorSnackBar('Failed to toggle like');
    }
  }

  Future<void> _toggleSubscription() async {
    if (!AnilistThreadsService.hasAnilistToken) {
      snackBar('Log in to AniList to subscribe to threads');
      return;
    }
    final target = !_thread.isSubscribed;
    final prev = _thread;
    setState(() => _thread = _thread.copyWith(isSubscribed: target));
    widget.onThreadUpdated?.call(_thread);

    final res =
        await AnilistThreadsService.toggleThreadSubscription(_thread.id, target);
    if (!mounted) return;
    if (res != null) {
      setState(() => _thread = _thread.copyWith(isSubscribed: res));
      widget.onThreadUpdated?.call(_thread);
      snackBar(res ? 'Subscribed to thread' : 'Unsubscribed from thread');
    } else {
      setState(() => _thread = prev);
      widget.onThreadUpdated?.call(_thread);
      errorSnackBar('Failed to update subscription');
    }
  }

  List<AnilistThreadComment> _updateCommentInTree(
    List<AnilistThreadComment> list,
    int targetId,
    AnilistThreadComment Function(AnilistThreadComment) updater,
  ) {
    return list.map((c) {
      if (c.id == targetId) {
        return updater(c);
      }
      if (c.childComments.isNotEmpty) {
        return c.copyWith(
          childComments: _updateCommentInTree(c.childComments, targetId, updater),
        );
      }
      return c;
    }).toList();
  }

  List<AnilistThreadComment> _removeCommentFromTree(
    List<AnilistThreadComment> list,
    int targetId,
  ) {
    final result = <AnilistThreadComment>[];
    for (final c in list) {
      if (c.id == targetId) continue;
      if (c.childComments.isNotEmpty) {
        result.add(c.copyWith(
          childComments: _removeCommentFromTree(c.childComments, targetId),
        ));
      } else {
        result.add(c);
      }
    }
    return result;
  }

  Future<void> _toggleCommentLike(AnilistThreadComment comment) async {
    if (!AnilistThreadsService.hasAnilistToken) {
      snackBar('Log in to AniList to like comments');
      return;
    }
    final prev = _comments;
    setState(() {
      _comments = _updateCommentInTree(
        _comments,
        comment.id,
        (c) => c.copyWith(
          isLiked: !c.isLiked,
          likeCount: c.isLiked
              ? (c.likeCount - 1).clamp(0, 1 << 30)
              : c.likeCount + 1,
        ),
      );
    });

    final res = await AnilistThreadsService.toggleThreadCommentLike(comment.id);
    if (!mounted) return;
    if (res != null) {
      setState(() {
        _comments = _updateCommentInTree(
          _comments,
          comment.id,
          (c) => c.copyWith(likeCount: res.likeCount, isLiked: res.isLiked),
        );
      });
    } else {
      setState(() => _comments = prev);
      errorSnackBar('Failed to toggle like');
    }
  }

  Future<void> _deleteComment(AnilistThreadComment comment) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete comment?'),
        content: const Text('This comment will be removed from AniList.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final ok = await AnilistThreadsService.deleteThreadComment(comment.id);
    if (!mounted) return;
    if (ok) {
      setState(() {
        _comments = _removeCommentFromTree(_comments, comment.id);
        _thread = _thread.copyWith(
          replyCount: (_thread.replyCount - 1).clamp(0, 1 << 30),
        );
      });
      widget.onThreadUpdated?.call(_thread);
      successSnackBar('Comment deleted');
    } else {
      errorSnackBar('Failed to delete comment');
    }
  }

  Future<bool> _submitReply(String text, int? parentCommentId) async {
    if (!AnilistThreadsService.hasAnilistToken) {
      snackBar('Log in to AniList to post comments');
      return false;
    }

    final saved = await AnilistThreadsService.saveThreadComment(
      threadId: _thread.id,
      comment: text,
      parentCommentId: parentCommentId,
    );
    if (!mounted) return saved != null;

    if (saved != null) {
      if (parentCommentId != null) {
        _expandedCommentIds.add(parentCommentId);
      }
      setState(() {
        _thread = _thread.copyWith(replyCount: _thread.replyCount + 1);
      });
      widget.onThreadUpdated?.call(_thread);
      successSnackBar('Reply posted');
      _loadInitial(refreshThread: false);
      return true;
    } else {
      errorSnackBar('Failed to post reply');
      return false;
    }
  }

  void _focusComposer({
    AnilistThreadComment? replyTo,
    bool resetTarget = false,
  }) {
    if (_thread.isLocked) {
      snackBar('This thread is locked');
      return;
    }
    if (!AnilistThreadsService.hasAnilistToken) {
      snackBar('Log in to AniList to post comments');
      return;
    }
    if (resetTarget) {
      _replyingToNotifier.value = null;
    } else if (replyTo != null) {
      if (_replyingToNotifier.value?.id == replyTo.id) {
        _replyingToNotifier.value = null;
      } else {
        _replyingToNotifier.value = replyTo;
      }
    }
    _composerFocusNode.requestFocus();
  }

  Future<void> _openInBrowser() async {
    final rawUrl = _thread.siteUrl?.isNotEmpty == true
        ? _thread.siteUrl!
        : 'https://anilist.co/forum/thread/${_thread.id}';
    final uri = Uri.tryParse(rawUrl);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _openUserProfile(AnilistThreadUser? user) {
    if (user == null || user.id <= 0) return;
    navigate(() => UserProfilePage(userId: user.id));
  }

  String _relativeTime(int epochSeconds) {
    if (epochSeconds <= 0) return '';
    return formatTimeAgo(epochSeconds * 1000);
  }

  bool _isDetailsOled(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (!isDark) return false;
    return settingsController.detailsOledMode;
  }

  Widget _buildDetailsBackdrop(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDetailsOled = _isDetailsOled(context);
    final blurScope = settingsController.detailsBlurScope;

    if (isDetailsOled) {
      return Container(color: Colors.black);
    }

    if (blurScope == 0) {
      return Container(color: colors.surface);
    }

    final media = widget.media;
    final posterUrl = media?.poster ?? '';
    final effectiveCover =
        (media?.cover?.isNotEmpty == true ? media!.cover! : posterUrl);
    final usePoster = settingsController.usePosterForBlur;
    final blurSourceUrl = usePoster ? posterUrl : effectiveCover;
    final blurFallbackUrl = usePoster ? effectiveCover : posterUrl;
    final tintBlur = settingsController.tintBlur;
    final blurColor = tintBlur ? colors.primary.opaque(0.4) : null;
    final isMesh = settingsController.detailsBlurStyle == 1;
    final isBaked = isMesh || settingsController.useComputedBlur;
    final blurAmount = UISettingsKeys.detailsBlurAmount.get<double>(20.0);
    final brightness =
        UISettingsKeys.detailsBackdropBrightness.get<double>(1.0);
    final baseArtworkColor = tintBlur
        ? colors.primary
        : (AnymeXScaffold.parseColor(widget.posterColorHex) ?? colors.primary);
    final gradientBgColor = Color.alphaBlend(
      baseArtworkColor.withValues(alpha: isDark ? 0.20 : 0.12),
      colors.surface,
    );

    Widget buildBlur({double? height}) {
      if (blurSourceUrl.isEmpty) {
        return Container(
          height: height ?? double.infinity,
          width: double.infinity,
          color: gradientBgColor,
        );
      }
      if (isBaked) {
        return BakedBlurImage(
          url: blurSourceUrl,
          fallback: blurFallbackUrl,
          saturation: 1.0,
          blurAmount: blurAmount,
          brightness: brightness,
          color: blurColor,
          fit: BoxFit.cover,
          height: height,
          width: double.infinity,
          fadeBottom: true,
          isMesh: isMesh,
        );
      }
      return ColorFiltered(
        colorFilter: ColorFilter.matrix([
          brightness,
          0,
          0,
          0,
          0,
          0,
          brightness,
          0,
          0,
          0,
          0,
          0,
          brightness,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ]),
        child: ImageFiltered(
          enabled: blurAmount > 0,
          imageFilter: ImageFilter.blur(
            sigmaX: blurAmount,
            sigmaY: blurAmount,
          ),
          child: AnymeXImage(
            imageUrl: blurSourceUrl,
            errorImage: blurFallbackUrl,
            radius: 0,
            fit: BoxFit.cover,
            width: double.infinity,
            height: height ?? double.infinity,
            color: blurColor,
            memCacheWidth: blurAmount > 2 ? 80 : null,
          ),
        ),
      );
    }

    if (blurScope == 2) {
      final washHeight =
          (MediaQuery.sizeOf(context).height * 0.48).clamp(320.0, 520.0);
      return Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: Container(color: gradientBgColor)),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: washHeight,
            child: RepaintBoundary(child: buildBlur(height: washHeight)),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: washHeight + 1.0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.30, 0.60, 0.85, 1.0],
                  colors: [
                    gradientBgColor.withValues(alpha: isDark ? 0.30 : 0.10),
                    gradientBgColor.withValues(alpha: isDark ? 0.55 : 0.25),
                    gradientBgColor.withValues(alpha: isDark ? 0.85 : 0.65),
                    gradientBgColor,
                    gradientBgColor,
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    // blurScope == 1: Full Screen Blur
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: RepaintBoundary(child: buildBlur())),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  colors.surface.withValues(alpha: 0.40),
                  colors.surface.withValues(alpha: 0.65),
                  colors.surface.withValues(alpha: 0.90),
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveTheme = widget.inheritedTheme ?? Theme.of(context);
    return Theme(
      data: effectiveTheme,
      child: Builder(builder: _buildPage),
    );
  }

  Widget _buildPage(BuildContext context) {
    final colors = context.colors;
    final isOled = _isDetailsOled(context);

    return AnymeXScaffold(
      disabled: true,
      isOled: isOled,
      color: isOled ? '' : widget.posterColorHex,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: Obx(() {
                final _ = settingsController.detailsOledMode;
                final __ = settingsController.detailsBlurScope;
                return _buildDetailsBackdrop(context);
              }),
            ),
          ),
          Scaffold(
            resizeToAvoidBottomInset: false,
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          titleSpacing: 0,
          title: const AnymeXText(
            'AniList Thread',
            size: 16,
            variant: TextVariant.bold,
          ),
          actions: [
            IconButton(
              tooltip: _thread.isSubscribed ? 'Unsubscribe' : 'Subscribe',
              icon: Icon(
                _thread.isSubscribed
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_none_rounded,
                color: _thread.isSubscribed ? colors.primary : null,
              ),
              onPressed: _toggleSubscription,
            ),
            IconButton(
              tooltip: 'Open on AniList',
              icon: const Icon(Icons.open_in_new_rounded, size: 20),
              onPressed: _openInBrowser,
            ),
          ],
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => FocusScope.of(context).unfocus(),
                child: RepaintBoundary(
                  child: RefreshIndicator(
                    onRefresh: () => _loadInitial(refreshThread: true),
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      slivers: [
                        SliverToBoxAdapter(
                          child: _buildThreadPost(context),
                        ),
                        SliverToBoxAdapter(
                          child: _buildCommentsHeader(context),
                        ),
                        if (_isLoading)
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 40),
                              child: Center(child: CircularProgressIndicator()),
                            ),
                          )
                        else if (_comments.isEmpty)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 36,
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.chat_bubble_outline_rounded,
                                    size: 36,
                                    color: colors.onSurfaceVariant
                                        .opaque(0.5, iReallyMeanIt: true),
                                  ),
                                  const SizedBox(height: 10),
                                  AnymeXText(
                                    'No comments yet. Be the first to reply!',
                                    size: 13,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          SliverToBoxAdapter(
                            child: Container(
                              margin:
                                  const EdgeInsets.fromLTRB(14, 6, 14, 120),
                              decoration: BoxDecoration(
                                color: isOled
                                    ? Colors.white.withValues(alpha: 0.03)
                                    : colors.surfaceContainer
                                        .opaque(0.35, iReallyMeanIt: true),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: colors.onSurface
                                      .opaque(0.08, iReallyMeanIt: true),
                                  width: 1,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      14,
                                      16,
                                      14,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        for (int i = 0;
                                            i < _comments.length;
                                            i++) ...[
                                          if (i > 0)
                                            Container(
                                              height: 1,
                                              margin:
                                                  const EdgeInsets.symmetric(
                                                vertical: 14,
                                              ),
                                              color: colors.outlineVariant
                                                  .opaque(0.18,
                                                      iReallyMeanIt: true),
                                            ),
                                          _buildCommentNode(
                                            context,
                                            _comments[i],
                                            depth: 0,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  if (_hasNextPage)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        0,
                                        16,
                                        16,
                                      ),
                                      child: Center(
                                        child: _isLoadingMore
                                            ? const SizedBox(
                                                width: 24,
                                                height: 24,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2.2,
                                                ),
                                              )
                                            : OutlinedButton.icon(
                                                onPressed: _loadMoreComments,
                                                icon: const Icon(
                                                  Icons.expand_more_rounded,
                                                ),
                                                label: const Text(
                                                  'Load more comments',
                                                ),
                                              ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        if (_comments.isEmpty)
                          const SliverToBoxAdapter(
                            child: SizedBox(height: 120),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: AnilistThreadComposer(
                controller: _replyController,
                focusNode: _composerFocusNode,
                replyingToNotifier: _replyingToNotifier,
                onSubmit: _submitReply,
                isLocked: _thread.isLocked,
                hasAuthToken: AnilistThreadsService.hasAnilistToken,
              ),
            ),
          ],
        ),
          ),
        ],
      ),
    );
  }

  Widget _buildThreadPost(BuildContext context) {
    final colors = context.colors;
    final isOled = _isDetailsOled(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isOled
            ? Colors.white.withValues(alpha: 0.03)
            : colors.surfaceContainer.opaque(0.35, iReallyMeanIt: true),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colors.onSurface.opaque(0.08, iReallyMeanIt: true),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Thread Title
          AnymeXText(
            _thread.title,
            size: 18,
            variant: TextVariant.bold,
            maxLines: 5,
          ),
          // Row 2: Thread Categories
          if (_thread.isSticky ||
              _thread.isLocked ||
              _thread.categories.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (_thread.isSticky)
                  _badge(
                    context,
                    'Pinned',
                    icon: Icons.push_pin_rounded,
                    highlight: true,
                  ),
                if (_thread.isLocked)
                  _badge(
                    context,
                    'Locked',
                    icon: Icons.lock_outline_rounded,
                  ),
                for (final cat in _thread.categories)
                  if (cat.name.isNotEmpty) _badge(context, cat.name),
              ],
            ),
          ],
          // Row 3: [Avatar] nama_akun · date (no views!) | [Love] [Comment]
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _openUserProfile(_thread.user),
                  child: Row(
                    children: [
                      _avatar(context, _thread.user?.avatarUrl, size: 30),
                      const SizedBox(width: 10),
                      Flexible(
                        child: AnymeXText(
                          _thread.user?.name ?? 'Unknown',
                          size: 13.5,
                          variant: TextVariant.semiBold,
                          color: colors.primary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_thread.createdAt > 0) ...[
                        const SizedBox(width: 6),
                        AnymeXText(
                          '· ${_relativeTime(_thread.createdAt)}',
                          size: 11.5,
                          color: colors.onSurfaceVariant,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: _toggleThreadLike,
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _thread.isLiked
                        ? colors.primary.withValues(alpha: 0.16)
                        : colors.onSurface.opaque(0.06, iReallyMeanIt: true),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _thread.isLiked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        size: 16,
                        color: _thread.isLiked
                            ? colors.primary
                            : colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 5),
                      AnymeXText(
                        '${_thread.likeCount}',
                        size: 12,
                        variant: TextVariant.semiBold,
                        color: _thread.isLiked
                            ? colors.primary
                            : colors.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: () => _focusComposer(resetTarget: true),
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: colors.onSurface.opaque(0.06, iReallyMeanIt: true),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 15,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 5),
                      AnymeXText(
                        '${_thread.replyCount}',
                        size: 12,
                        variant: TextVariant.semiBold,
                        color: colors.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_thread.bodyHtml.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Divider(
              height: 1,
              color: colors.outlineVariant.opaque(0.25, iReallyMeanIt: true),
            ),
            const SizedBox(height: 12),
            AnilistAboutMe(about: _thread.bodyHtml),
          ],
        ],
      ),
    );
  }

  Widget _buildCommentsHeader(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 12, 6),
      child: Row(
        children: [
          AnymeXText(
            'Comments (${_thread.replyCount})',
            size: 14,
            variant: TextVariant.bold,
          ),
          const Spacer(),
          PopupMenuButton<String>(
            initialValue: _commentSort,
            onSelected: (val) {
              if (val == _commentSort) return;
              setState(() => _commentSort = val);
              _loadInitial(refreshThread: false);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'ID', child: Text('Oldest first')),
              PopupMenuItem(value: 'ID_DESC', child: Text('Newest first')),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.sort_rounded,
                    size: 16,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  AnymeXText(
                    _commentSort == 'ID' ? 'Oldest' : 'Newest',
                    size: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  int _countDescendants(AnilistThreadComment comment) {
    int total = 0;
    for (final child in comment.childComments) {
      total += 1 + _countDescendants(child);
    }
    return total;
  }

  Widget _buildCommentNode(
    BuildContext context,
    AnilistThreadComment comment, {
    required int depth,
  }) {
    final colors = context.colors;
    final isTopLevel = depth == 0;
    final isOwn = _currentUserId != null && comment.userId == _currentUserId;
    final hasChildren = comment.childComments.isNotEmpty;
    final isExpanded = _expandedCommentIds.contains(comment.id);
    final totalReplies = hasChildren ? _countDescendants(comment) : 0;

    final railColor = switch (depth % 3) {
      1 => colors.primary.withValues(alpha: 0.45),
      2 => colors.secondary.withValues(alpha: 0.45),
      _ => colors.tertiary.withValues(alpha: 0.45),
    };

    final bodyWidget = AnilistAboutMe(about: comment.commentHtml);

    final commentContent = ValueListenableBuilder<AnilistThreadComment?>(
      valueListenable: _replyingToNotifier,
      child: bodyWidget,
      builder: (context, activeReplyTarget, cachedBody) {
        final isReplyTarget = activeReplyTarget?.id == comment.id;

        return Container(
          padding: isReplyTarget ? const EdgeInsets.all(8) : EdgeInsets.zero,
          decoration: isReplyTarget
              ? BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: [Avatar] nama_akun · date on left | [Love] [Reply icon] on right
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _openUserProfile(comment.user),
                      child: Row(
                        children: [
                          _avatar(
                            context,
                            comment.user?.avatarUrl,
                            size: isTopLevel ? 28 : 22,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: AnymeXText(
                              comment.user?.name ?? 'Unknown',
                              size: isTopLevel ? 13.5 : 12.5,
                              variant: TextVariant.bold,
                              color: colors.primary,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (comment.createdAt > 0) ...[
                            const SizedBox(width: 6),
                            AnymeXText(
                              '· ${_relativeTime(comment.createdAt)}',
                              size: 11,
                              color: colors.onSurfaceVariant,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () => _toggleCommentLike(comment),
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            comment.isLiked
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            size: 15,
                            color: comment.isLiked
                                ? colors.primary
                                : colors.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          AnymeXText(
                            '${comment.likeCount}',
                            size: 11.5,
                            variant: TextVariant.semiBold,
                            color: comment.isLiked
                                ? colors.primary
                                : colors.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (!_thread.isLocked && !comment.isLocked) ...[
                    const SizedBox(width: 2),
                    Tooltip(
                      message: 'Reply',
                      child: InkWell(
                        onTap: () => _focusComposer(replyTo: comment),
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                          padding: const EdgeInsets.all(5),
                          child: Icon(
                            Icons.reply_rounded,
                            size: 16,
                            color: isReplyTarget
                                ? colors.primary
                                : colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (isOwn) ...[
                    const SizedBox(width: 2),
                    InkWell(
                      onTap: () => _deleteComment(comment),
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: Icon(
                          Icons.delete_outline_rounded,
                          size: 15,
                          color: colors.error,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              // Row 2: Comment body aligned flush-left with avatar (just like Thread Post)
              const SizedBox(height: 8),
              cachedBody!,
              // Row 3: Expand/collapse replies indicator + count ONLY (no "replies/hide" text)
              if (hasChildren) ...[
                const SizedBox(height: 6),
                InkWell(
                  onTap: () {
                    setState(() {
                      if (isExpanded) {
                        _expandedCommentIds.remove(comment.id);
                      } else {
                        _expandedCommentIds.add(comment.id);
                      }
                    });
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isExpanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          size: 17,
                          color: colors.primary,
                        ),
                        const SizedBox(width: 2),
                        AnymeXText(
                          '$totalReplies',
                          size: 12,
                          variant: TextVariant.bold,
                          color: colors.primary,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );

    final childrenWidget = (hasChildren && isExpanded)
        ? Container(
            margin: EdgeInsets.only(
              left: isTopLevel ? 12.0 : (depth < 4 ? 10.0 : 0.0),
              top: 8.0,
            ),
            padding: const EdgeInsets.only(left: 12.0),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: railColor,
                  width: 2.0,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < comment.childComments.length; i++)
                  Padding(
                    padding: EdgeInsets.only(top: i == 0 ? 0.0 : 12.0),
                    child: _buildCommentNode(
                      context,
                      comment.childComments[i],
                      depth: depth + 1,
                    ),
                  ),
              ],
            ),
          )
        : const SizedBox.shrink();

    final node = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        commentContent,
        childrenWidget,
      ],
    );
    return isTopLevel ? RepaintBoundary(child: node) : node;
  }

  Widget _avatar(BuildContext context, String? url, {double size = 28}) {
    final colors = context.colors;
    if (url != null && url.isNotEmpty) {
      return ClipOval(
        child: AnymeXImage(
          imageUrl: url,
          width: size,
          height: size,
          radius: size / 2,
          fit: BoxFit.cover,
        ),
      );
    }
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: colors.primary.withValues(alpha: 0.15),
      child:
          Icon(Icons.person_rounded, size: size * 0.6, color: colors.primary),
    );
  }

  Widget _badge(
    BuildContext context,
    String text, {
    IconData? icon,
    bool highlight = false,
  }) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: highlight
            ? colors.primary.withValues(alpha: 0.16)
            : colors.onSurface.opaque(0.08, iReallyMeanIt: true),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 12,
              color: highlight ? colors.primary : colors.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
          ],
          AnymeXText(
            text,
            size: 10.5,
            variant: TextVariant.semiBold,
            color: highlight ? colors.primary : colors.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}
