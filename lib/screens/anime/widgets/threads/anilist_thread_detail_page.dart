import 'package:anymex/controllers/services/anilist/anilist_auth.dart';
import 'package:anymex/controllers/services/anilist/anilist_threads_service.dart';
import 'package:anymex/models/Anilist/anilist_thread.dart';
import 'package:anymex/screens/anime/widgets/threads/anilist_thread_composer.dart';
import 'package:anymex/screens/profile/user_profile_page.dart';
import 'package:anymex/utils/al_about_me.dart';
import 'package:anymex/utils/function.dart';
import 'package:anymex/utils/theme_extensions.dart';
import 'package:anymex/widgets/anymex_widgets/anymex_image.dart';
import 'package:anymex/widgets/anymex_widgets/anymex_text.dart';
import 'package:anymex/widgets/non_widgets/snackbar.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

class AnilistThreadDetailPage extends StatefulWidget {
  final AnilistThread initialThread;
  final ValueChanged<AnilistThread>? onThreadUpdated;

  const AnilistThreadDetailPage({
    super.key,
    required this.initialThread,
    this.onThreadUpdated,
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
  int _page = 1;
  String _commentSort = 'ID'; // 'ID' = Oldest, 'ID_DESC' = Newest

  final TextEditingController _replyController = TextEditingController();
  final FocusNode _replyFocusNode = FocusNode();
  final ValueNotifier<AnilistThreadComment?> _replyingToNotifier =
      ValueNotifier<AnilistThreadComment?>(null);
  bool _isSendingReply = false;
  final Set<int> _collapsedCommentIds = {};

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
    _replyFocusNode.dispose();
    _replyingToNotifier.dispose();
    super.dispose();
  }

  Future<void> _loadInitial({bool refreshThread = true}) async {
    setState(() {
      _isLoading = true;
      _page = 1;
    });

    final futures = await Future.wait([
      if (refreshThread) AnilistThreadsService.fetchThreadDetail(_thread.id),
      AnilistThreadsService.fetchThreadComments(
        threadId: _thread.id,
        page: 1,
        sort: _commentSort,
      ),
    ]);

    if (!mounted) return;

    int commentResultIdx = 0;
    if (refreshThread) {
      final fetchedThread = futures[0] as AnilistThread?;
      if (fetchedThread != null) {
        _thread = fetchedThread;
        widget.onThreadUpdated?.call(_thread);
      }
      commentResultIdx = 1;
    }

    final (comments, hasNext) =
        futures[commentResultIdx] as (List<AnilistThreadComment>, bool);

    setState(() {
      _comments = comments;
      _hasNextPage = hasNext;
      _isLoading = false;
    });
  }

  Future<void> _loadMoreComments() async {
    if (_isLoadingMore || !_hasNextPage) return;
    setState(() => _isLoadingMore = true);
    final nextPage = _page + 1;
    final (more, hasNext) = await AnilistThreadsService.fetchThreadComments(
      threadId: _thread.id,
      page: nextPage,
      sort: _commentSort,
    );
    if (!mounted) return;
    setState(() {
      _page = nextPage;
      _comments = [..._comments, ...more];
      _hasNextPage = hasNext;
      _isLoadingMore = false;
    });
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

  Future<void> _submitReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty || _isSendingReply) return;
    if (!AnilistThreadsService.hasAnilistToken) {
      snackBar('Log in to AniList to post comments');
      return;
    }

    setState(() => _isSendingReply = true);
    final saved = await AnilistThreadsService.saveThreadComment(
      threadId: _thread.id,
      comment: text,
      parentCommentId: _replyingToNotifier.value?.id,
    );
    if (!mounted) return;

    setState(() => _isSendingReply = false);
    if (saved != null) {
      _replyController.clear();
      _replyFocusNode.unfocus();
      _replyingToNotifier.value = null;
      setState(() {
        _thread = _thread.copyWith(replyCount: _thread.replyCount + 1);
      });
      widget.onThreadUpdated?.call(_thread);
      successSnackBar('Reply posted');
      await _loadInitial(refreshThread: false);
    } else {
      errorSnackBar('Failed to post reply');
    }
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

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: colors.surface,
      appBar: AppBar(
        backgroundColor: colors.surface,
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
                            horizontal: 24, vertical: 36),
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
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 160),
                      sliver: SliverList.builder(
                        itemCount: _comments.length + (_hasNextPage ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _comments.length) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              child: Center(
                                child: _isLoadingMore
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2.2),
                                      )
                                    : OutlinedButton.icon(
                                        onPressed: _loadMoreComments,
                                        icon: const Icon(
                                            Icons.expand_more_rounded),
                                        label: const Text('Load more comments'),
                                      ),
                              ),
                            );
                          }
                          return _buildCommentNode(
                            context,
                            _comments[index],
                            depth: 0,
                          );
                        },
                      ),
                    ),
                  if (_comments.isEmpty)
                    const SliverToBoxAdapter(child: SizedBox(height: 150)),
                ],
              ),
            ),
            ),
          ),
          _KeyboardFloatingComposer(
            surfaceColor: colors.surface,
            controller: _replyController,
            focusNode: _replyFocusNode,
            replyingToNotifier: _replyingToNotifier,
            onSend: _submitReply,
            isSending: _isSendingReply,
            isLocked: _thread.isLocked,
            hasAuthToken: AnilistThreadsService.hasAnilistToken,
          ),
        ],
      ),
    );
  }

  void _focusThreadCommentComposer() {
    if (_thread.isLocked) {
      snackBar('This thread is locked');
      return;
    }
    if (!AnilistThreadsService.hasAnilistToken) {
      snackBar('Log in to AniList to post comments');
      return;
    }
    _replyingToNotifier.value = null;
    _replyFocusNode.requestFocus();
  }

  Widget _buildThreadPost(BuildContext context) {
    final colors = context.colors;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.opaque(0.28, iReallyMeanIt: true),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colors.outlineVariant.opaque(0.25, iReallyMeanIt: true),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Thread Title (top)
          AnymeXText(
            _thread.title,
            size: 18,
            variant: TextVariant.bold,
            maxLines: 5,
          ),
          // Row 2: Thread Categories (below title)
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
          // Row 3: Thread Author on left | Love + Comment buttons on right
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _openUserProfile(_thread.user),
                  child: Row(
                    children: [
                      _avatar(context, _thread.user?.avatarUrl, size: 32),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AnymeXText(
                              _thread.user?.name ?? 'Unknown',
                              size: 13.5,
                              variant: TextVariant.semiBold,
                              color: colors.primary,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (_thread.createdAt > 0)
                              AnymeXText(
                                '${_relativeTime(_thread.createdAt)} · ${_thread.viewCount} views',
                                size: 11,
                                color: colors.onSurfaceVariant,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
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
                onTap: _focusThreadCommentComposer,
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
          // Body
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
                  Icon(Icons.sort_rounded,
                      size: 16, color: colors.onSurfaceVariant),
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
    String? parentAuthorName,
  }) {
    final colors = context.colors;
    final isTopLevel = depth == 0;
    final isOwn = _currentUserId != null && comment.userId == _currentUserId;
    final isOp = _thread.userId > 0 && comment.userId == _thread.userId;
    final hasChildren = comment.childComments.isNotEmpty;
    final isCollapsed = _collapsedCommentIds.contains(comment.id);
    final totalReplies = hasChildren ? _countDescendants(comment) : 0;

    final railColor = switch (depth % 3) {
      1 => colors.primary.withValues(alpha: 0.45),
      2 => colors.secondary.withValues(alpha: 0.45),
      _ => colors.tertiary.withValues(alpha: 0.45),
    };

    final bodyWidget = AnilistAboutMe(about: comment.commentHtml);

    final card = ValueListenableBuilder<AnilistThreadComment?>(
      valueListenable: _replyingToNotifier,
      child: bodyWidget,
      builder: (context, activeReplyTarget, cachedBody) {
        final isReplyTarget = activeReplyTarget?.id == comment.id;
        final cardColor = isReplyTarget
            ? colors.primary.withValues(alpha: 0.12)
            : (isTopLevel
                ? colors.surfaceContainerHighest
                    .opaque(0.30, iReallyMeanIt: true)
                : colors.surfaceContainer.opaque(0.55, iReallyMeanIt: true));

        final cardBorderColor = isReplyTarget
            ? colors.primary.withValues(alpha: 0.65)
            : (isTopLevel
                ? colors.outlineVariant.opaque(0.28, iReallyMeanIt: true)
                : colors.outlineVariant.opaque(0.16, iReallyMeanIt: true));

        return Container(
          padding: EdgeInsets.all(isTopLevel ? 14 : 10),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(isTopLevel ? 16 : 12),
            border: Border.all(
              color: cardBorderColor,
              width: isReplyTarget ? 1.4 : 1.0,
            ),
          ),
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isTopLevel &&
              parentAuthorName != null &&
              parentAuthorName.isNotEmpty) ...[
            Row(
              children: [
                Icon(
                  Icons.subdirectory_arrow_right_rounded,
                  size: 13,
                  color: colors.primary.withValues(alpha: 0.85),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: AnymeXText(
                    'Replying to @$parentAuthorName',
                    size: 11,
                    variant: TextVariant.semiBold,
                    color: colors.onSurfaceVariant,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          // Row 1: Author + time on left | Love + Reply icon (no text) on right
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
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
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
                                if (isOp) ...[
                                  const SizedBox(width: 5),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          colors.primary.withValues(alpha: 0.18),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: AnymeXText(
                                      'OP',
                                      size: 9,
                                      variant: TextVariant.bold,
                                      color: colors.primary,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (comment.createdAt > 0)
                              AnymeXText(
                                _relativeTime(comment.createdAt),
                                size: 10.5,
                                color: colors.onSurfaceVariant,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Love button on right
              InkWell(
                onTap: () => _toggleCommentLike(comment),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                  decoration: BoxDecoration(
                    color: comment.isLiked
                        ? colors.primary.withValues(alpha: 0.16)
                        : colors.onSurface.opaque(0.05, iReallyMeanIt: true),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        comment.isLiked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        size: 14,
                        color: comment.isLiked
                            ? colors.primary
                            : colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      AnymeXText(
                        '${comment.likeCount}',
                        size: 11,
                        variant: TextVariant.semiBold,
                        color: comment.isLiked
                            ? colors.primary
                            : colors.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
              // Icon-only Reply button on right (no "Reply" text)
              if (!_thread.isLocked && !comment.isLocked) ...[
                const SizedBox(width: 4),
                Tooltip(
                  message: 'Reply',
                  child: InkWell(
                    onTap: () {
                      if (_replyingToNotifier.value?.id == comment.id) {
                        _replyingToNotifier.value = null;
                      } else {
                        _replyingToNotifier.value = comment;
                        _replyFocusNode.requestFocus();
                      }
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: isReplyTarget
                            ? colors.primary.withValues(alpha: 0.18)
                            : colors.onSurface.opaque(0.05, iReallyMeanIt: true),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.reply_rounded,
                        size: 15,
                        color: isReplyTarget
                            ? colors.primary
                            : colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
              if (isOwn) ...[
                const SizedBox(width: 4),
                InkWell(
                  onTap: () => _deleteComment(comment),
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
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
          SizedBox(height: isTopLevel ? 10 : 7),
          cachedBody!,
          // Bottom row (former love button spot): indicator + count ONLY (no "reply/replies/hide" text)
          if (hasChildren) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: () {
                setState(() {
                  if (isCollapsed) {
                    _collapsedCommentIds.remove(comment.id);
                  } else {
                    _collapsedCommentIds.add(comment.id);
                  }
                });
              },
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                decoration: BoxDecoration(
                  color: colors.onSurface.opaque(0.06, iReallyMeanIt: true),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isCollapsed
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_up_rounded,
                      size: 16,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 2),
                    AnymeXText(
                      '$totalReplies',
                      size: 11.5,
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

    final childrenWidget = (hasChildren && !isCollapsed)
        ? Container(
            margin: EdgeInsets.only(
              left: isTopLevel ? 14.0 : (depth < 4 ? 10.0 : 0.0),
              top: 6.0,
            ),
            padding: const EdgeInsets.only(left: 12.0),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: railColor,
                  width: 2.2,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < comment.childComments.length; i++)
                  Padding(
                    padding: EdgeInsets.only(top: i == 0 ? 0.0 : 6.0),
                    child: _buildCommentNode(
                      context,
                      comment.childComments[i],
                      depth: depth + 1,
                      parentAuthorName: comment.user?.name,
                    ),
                  ),
              ],
            ),
          )
        : const SizedBox.shrink();

    final node = Padding(
      padding: EdgeInsets.only(top: isTopLevel ? 10.0 : 0.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          card,
          childrenWidget,
        ],
      ),
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
      child: Icon(Icons.person_rounded, size: size * 0.6, color: colors.primary),
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

class _KeyboardFloatingComposer extends StatelessWidget {
  final Color surfaceColor;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueNotifier<AnilistThreadComment?> replyingToNotifier;
  final Future<void> Function() onSend;
  final bool isSending;
  final bool isLocked;
  final bool hasAuthToken;

  const _KeyboardFloatingComposer({
    required this.surfaceColor,
    required this.controller,
    required this.focusNode,
    required this.replyingToNotifier,
    required this.onSend,
    required this.isSending,
    required this.isLocked,
    required this.hasAuthToken,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Positioned(
      left: 0,
      right: 0,
      bottom: bottomInset,
      child: RepaintBoundary(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                surfaceColor.withValues(alpha: 0.0),
                surfaceColor.withValues(alpha: 0.88),
                surfaceColor,
              ],
              stops: const [0.0, 0.45, 1.0],
            ),
          ),
          padding: const EdgeInsets.only(top: 12),
          child: MediaQuery.removePadding(
            context: context,
            removeBottom: bottomInset > 0,
            child: ValueListenableBuilder<AnilistThreadComment?>(
              valueListenable: replyingToNotifier,
              builder: (context, replyingTo, _) {
                return AnilistThreadComposer(
                controller: controller,
                focusNode: focusNode,
                replyingTo: replyingTo,
                onCancelReply: () => replyingToNotifier.value = null,
                onSend: onSend,
                isSending: isSending,
                isLocked: isLocked,
                hasAuthToken: hasAuthToken,
              );
              },
            ),
          ),
        ),
      ),
    );
  }
}
