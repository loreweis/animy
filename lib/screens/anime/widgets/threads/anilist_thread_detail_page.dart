import 'package:anymex/controllers/services/anilist/anilist_auth.dart';
import 'package:anymex/controllers/services/anilist/anilist_threads_service.dart';
import 'package:anymex/models/Anilist/anilist_thread.dart';
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
  AnilistThreadComment? _replyingTo;
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
      parentCommentId: _replyingTo?.id,
    );
    if (!mounted) return;

    setState(() => _isSendingReply = false);
    if (saved != null) {
      _replyController.clear();
      _replyFocusNode.unfocus();
      setState(() {
        _replyingTo = null;
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
      body: Column(
        children: [
          Expanded(
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
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
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
                ],
              ),
            ),
          ),
          _buildComposerBar(context),
        ],
      ),
    );
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
          if (_thread.isSticky ||
              _thread.isLocked ||
              _thread.categories.isNotEmpty) ...[
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
            const SizedBox(height: 10),
          ],
          AnymeXText(
            _thread.title,
            size: 18,
            variant: TextVariant.bold,
            maxLines: 5,
          ),
          const SizedBox(height: 12),
          GestureDetector(
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
                      ),
                      if (_thread.createdAt > 0)
                        AnymeXText(
                          _relativeTime(_thread.createdAt),
                          size: 11,
                          color: colors.onSurfaceVariant,
                        ),
                    ],
                  ),
                ),
              ],
            ),
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
          const SizedBox(height: 14),
          Row(
            children: [
              InkWell(
                onTap: _toggleThreadLike,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _thread.isLiked
                        ? colors.primary.withValues(alpha: 0.16)
                        : colors.onSurface.opaque(0.06, iReallyMeanIt: true),
                    borderRadius: BorderRadius.circular(20),
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
                      const SizedBox(width: 6),
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
              const SizedBox(width: 10),
              Icon(Icons.chat_bubble_outline_rounded,
                  size: 15, color: colors.onSurfaceVariant),
              const SizedBox(width: 4),
              AnymeXText(
                '${_thread.replyCount}',
                size: 12,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Icon(Icons.visibility_outlined,
                  size: 15, color: colors.onSurfaceVariant),
              const SizedBox(width: 4),
              AnymeXText(
                '${_thread.viewCount}',
                size: 12,
                color: colors.onSurfaceVariant,
              ),
            ],
          ),
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

  Widget _buildCommentNode(
    BuildContext context,
    AnilistThreadComment comment, {
    required int depth,
  }) {
    final colors = context.colors;
    final clampedDepth = depth.clamp(0, 4);
    final isOwn = _currentUserId != null && comment.userId == _currentUserId;
    final hasChildren = comment.childComments.isNotEmpty;
    final isCollapsed = _collapsedCommentIds.contains(comment.id);

    return Container(
      margin: EdgeInsets.only(
        left: clampedDepth > 0 ? 12.0 : 0.0,
        top: depth == 0 ? 8.0 : 6.0,
      ),
      decoration: clampedDepth > 0
          ? BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: colors.primary.withValues(alpha: 0.28),
                  width: 2,
                ),
              ),
            )
          : null,
      padding: EdgeInsets.only(left: clampedDepth > 0 ? 10.0 : 0.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest
                  .opaque(depth == 0 ? 0.22 : 0.14, iReallyMeanIt: true),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: colors.outlineVariant.opaque(0.18, iReallyMeanIt: true),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => _openUserProfile(comment.user),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _avatar(context, comment.user?.avatarUrl, size: 26),
                          const SizedBox(width: 8),
                          AnymeXText(
                            comment.user?.name ?? 'Unknown',
                            size: 13,
                            variant: TextVariant.semiBold,
                            color: colors.primary,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (comment.createdAt > 0)
                      Expanded(
                        child: AnymeXText(
                          _relativeTime(comment.createdAt),
                          size: 11,
                          color: colors.onSurfaceVariant,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      )
                    else
                      const Spacer(),
                    if (hasChildren)
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
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isCollapsed
                                    ? Icons.unfold_more_rounded
                                    : Icons.unfold_less_rounded,
                                size: 15,
                                color: colors.onSurfaceVariant,
                              ),
                              const SizedBox(width: 2),
                              AnymeXText(
                                '${comment.childComments.length}',
                                size: 11,
                                color: colors.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                AnilistAboutMe(about: comment.commentHtml),
                const SizedBox(height: 8),
                Row(
                  children: [
                    InkWell(
                      onTap: () => _toggleCommentLike(comment),
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 4),
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
                              color: comment.isLiked
                                  ? colors.primary
                                  : colors.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (!_thread.isLocked && !comment.isLocked) ...[
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () {
                          setState(() => _replyingTo = comment);
                          _replyFocusNode.requestFocus();
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.reply_rounded,
                                size: 15,
                                color: colors.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              AnymeXText(
                                'Reply',
                                size: 11.5,
                                color: colors.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (isOwn) ...[
                      const Spacer(),
                      InkWell(
                        onTap: () => _deleteComment(comment),
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 4),
                          child: Icon(
                            Icons.delete_outline_rounded,
                            size: 16,
                            color: colors.error,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (hasChildren && !isCollapsed)
            for (final child in comment.childComments)
              _buildCommentNode(context, child, depth: depth + 1),
        ],
      ),
    );
  }

  Widget _buildComposerBar(BuildContext context) {
    final colors = context.colors;
    final hasToken = AnilistThreadsService.hasAnilistToken;

    if (_thread.isLocked) {
      return SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: colors.surfaceContainer,
            border: Border(
              top: BorderSide(
                color: colors.outlineVariant.opaque(0.25, iReallyMeanIt: true),
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline_rounded,
                  size: 16, color: colors.onSurfaceVariant),
              const SizedBox(width: 8),
              AnymeXText(
                'This thread is locked',
                size: 12.5,
                color: colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      );
    }

    if (!hasToken) {
      return SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: colors.surfaceContainer,
            border: Border(
              top: BorderSide(
                color: colors.outlineVariant.opaque(0.25, iReallyMeanIt: true),
              ),
            ),
          ),
          child: AnymeXText(
            'Log in to AniList to post replies or like comments',
            size: 12.5,
            color: colors.onSurfaceVariant,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: BoxDecoration(
          color: colors.surfaceContainer,
          border: Border(
            top: BorderSide(
              color: colors.outlineVariant.opaque(0.25, iReallyMeanIt: true),
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_replyingTo != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6, left: 4),
                child: Row(
                  children: [
                    Icon(Icons.reply_rounded, size: 14, color: colors.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: AnymeXText(
                        'Replying to ${_replyingTo!.user?.name ?? 'comment'}',
                        size: 12,
                        color: colors.primary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    InkWell(
                      onTap: () => setState(() => _replyingTo = null),
                      child: Icon(Icons.close_rounded,
                          size: 16, color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _replyController,
                    focusNode: _replyFocusNode,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: _replyingTo != null
                          ? 'Write a reply (Markdown supported)...'
                          : 'Write a comment (Markdown supported)...',
                      isDense: true,
                      filled: true,
                      fillColor: colors.surfaceContainerHighest
                          .opaque(0.4, iReallyMeanIt: true),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _isSendingReply ? null : _submitReply,
                  icon: _isSendingReply
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded, size: 18),
                ),
              ],
            ),
          ],
        ),
      ),
    );
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
