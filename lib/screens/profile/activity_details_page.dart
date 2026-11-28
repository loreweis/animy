import 'package:anymex/controllers/service_handler/service_handler.dart';
import 'package:anymex/controllers/services/anilist/anilist_auth.dart';
import 'package:anymex/controllers/services/anilist/anilist_threads_service.dart';
import 'package:anymex/controllers/settings/settings.dart';
import 'package:anymex/l10n/l10n_extension.dart';
import 'package:anymex/models/Anilist/anilist_activity.dart';
import 'package:anymex/screens/anime/widgets/threads/anilist_thread_composer.dart';
import 'package:anymex/screens/profile/profile_page.dart';
import 'package:anymex/screens/profile/user_profile_page.dart';
import 'package:anymex/utils/al_about_me.dart';
import 'package:anymex/utils/function.dart';
import 'package:anymex/utils/theme_extensions.dart';
import 'package:anymex/widgets/anymex_widgets/anymex_decorated_avatar.dart';
import 'package:anymex/widgets/anymex_widgets/anymex_image.dart';
import 'package:anymex/widgets/anymex_widgets/anymex_text.dart';
import 'package:anymex/widgets/non_widgets/activity_card.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

Future<void> showActivityDetailsSheet(
    BuildContext context, AnilistActivity activity) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return ActivityDetailsSheet(activity: activity);
    },
  );
}

class ActivityDetailsSheet extends StatefulWidget {
  final AnilistActivity activity;

  const ActivityDetailsSheet({super.key, required this.activity});

  @override
  State<ActivityDetailsSheet> createState() => _ActivityDetailsSheetState();
}

class _ActivityDetailsSheetState extends State<ActivityDetailsSheet> {
  List<ActivityReply>? replies;
  final TextEditingController _replyController = TextEditingController();
  final FocusNode _composerFocusNode = FocusNode();
  final ValueNotifier<ComposerBannerData?> _bannerNotifier =
      ValueNotifier<ComposerBannerData?>(null);
  final Map<int, GlobalKey> _replyKeys = {};

  int? _editingReplyId;
  int? _replyTargetId;
  String? _lastAutoMention;

  GlobalKey _keyForReply(int replyId) =>
      _replyKeys.putIfAbsent(replyId, () => GlobalKey());

  void _scrollToReply(int replyId) {
    final targetContext = _replyKeys[replyId]?.currentContext;
    if (targetContext != null) {
      Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        alignment: 0.2,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchReplies();
  }

  @override
  void dispose() {
    _replyController.dispose();
    _composerFocusNode.dispose();
    _bannerNotifier.dispose();
    super.dispose();
  }

  bool _isDetailsOled(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (!isDark) return false;
    return settingsController.detailsOledMode;
  }

  String _plainSnippet(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<bool> _confirmDiscard() async {
    if (_replyController.text.trim().isEmpty) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.theme.colorScheme.surfaceContainerHigh,
        title: AnymeXText(context.l10n.discardReply),
        content: AnymeXText(context.l10n.youHaveUnsentTextClosingNowWill),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: AnymeXText(
              context.l10n.cancel,
              style: TextStyle(color: ctx.theme.colorScheme.primary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: AnymeXText(
              context.l10n.actionDelete,
              style: TextStyle(color: ctx.theme.colorScheme.error),
            ),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  Future<void> _fetchReplies() async {
    final fetched =
        await Get.find<AnilistAuth>().fetchActivityReplies(widget.activity.id);
    if (mounted) {
      setState(() {
        replies = fetched;
      });
    }
  }

  void _clearBanner({bool clearTextIfEditing = false}) {
    final wasEditing = _editingReplyId != null;
    setState(() {
      _editingReplyId = null;
      _replyTargetId = null;
    });
    _lastAutoMention = null;
    _bannerNotifier.value = null;
    if (clearTextIfEditing && wasEditing) {
      _replyController.clear();
    }
  }

  Future<bool> _postReply(String text, int? _) async {
    if (!Get.find<AnilistAuth>().isLoggedIn.value) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AnymeXText(context.l10n.pleaseLoginFirst),
          duration: const Duration(milliseconds: 1500),
        ),
      );
      return false;
    }

    if (_editingReplyId != null) {
      final success = await Get.find<AnilistAuth>()
          .editActivityReply(_editingReplyId!, text);
      if (success && mounted) {
        _clearBanner();
        await _fetchReplies();
        return true;
      }
      return false;
    }

    final success = await Get.find<AnilistAuth>()
        .postActivityReply(widget.activity.id, text);

    if (success && mounted) {
      setState(() {
        widget.activity.replyCount++;
      });
      _clearBanner();
      await _fetchReplies();
      return true;
    }
    return false;
  }

  void _toggleReplyLike(ActivityReply reply) async {
    if (!Get.find<AnilistAuth>().isLoggedIn.value) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AnymeXText(context.l10n.pleaseLoginFirst),
          duration: const Duration(milliseconds: 1500),
        ),
      );
      return;
    }

    setState(() {
      reply.isLiked = !reply.isLiked;
      reply.likeCount += reply.isLiked ? 1 : -1;
    });

    final success =
        await Get.find<AnilistAuth>().toggleLike(reply.id, 'ACTIVITY_REPLY');

    if (!success && mounted) {
      setState(() {
        reply.isLiked = !reply.isLiked;
        reply.likeCount += reply.isLiked ? 1 : -1;
      });
    }
  }

  Future<void> _deleteReply(ActivityReply reply) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.theme.colorScheme.surfaceContainerHigh,
        title: AnymeXText(context.l10n.deleteReply),
        content: AnymeXText(context.l10n.areYouSureYouWantToDeleteThisReply),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: AnymeXText(context.l10n.cancel,
                style: TextStyle(color: context.theme.colorScheme.primary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: AnymeXText(context.l10n.delete,
                style: TextStyle(color: context.theme.colorScheme.error)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success =
          await Get.find<AnilistAuth>().deleteActivityReply(reply.id);
      if (success && mounted) {
        setState(() {
          widget.activity.replyCount = (widget.activity.replyCount > 0)
              ? widget.activity.replyCount - 1
              : 0;
        });
        await _fetchReplies();
      }
    }
  }

  void _editReply(ActivityReply reply) {
    final rawText =
        reply.text.replaceAll('<br>', '\n').replaceAll(RegExp(r'<[^>]*>'), '');
    setState(() {
      _editingReplyId = reply.id;
      _replyTargetId = reply.id;
    });
    _lastAutoMention = null;
    _bannerNotifier.value = ComposerBannerData(
      targetId: reply.id,
      title: 'Editing reply',
      subtitle: _plainSnippet(reply.text),
      onTap: () => _scrollToReply(reply.id),
    );
    _replyController.text = rawText;
    _replyController.selection = TextSelection.collapsed(offset: rawText.length);
    if (!_composerFocusNode.hasFocus) {
      _composerFocusNode.requestFocus();
    }
  }

  void _replyToUser(ActivityReply reply) {
    if (_replyTargetId == reply.id && _editingReplyId == null) {
      _clearBanner();
      return;
    }
    final wasEditing = _editingReplyId != null;
    final previousAutoMention = _lastAutoMention;
    final name = reply.authorName ?? 'User';
    final mention = '@$name ';

    setState(() {
      _editingReplyId = null;
      _replyTargetId = reply.id;
    });

    if (wasEditing) {
      _replyController.text = mention;
      _replyController.selection = TextSelection.collapsed(offset: mention.length);
    } else if (previousAutoMention != null &&
        _replyController.text.startsWith(previousAutoMention)) {
      final remainder = _replyController.text.substring(previousAutoMention.length);
      final next = '$mention$remainder';
      _replyController.text = next;
      _replyController.selection = TextSelection.collapsed(offset: next.length);
    } else if (!_replyController.text.contains(mention.trim())) {
      final current = _replyController.text;
      final next = current.isEmpty ? mention : '$current $mention';
      _replyController.text = next;
      _replyController.selection = TextSelection.collapsed(offset: next.length);
    }
    _lastAutoMention = mention;

    _bannerNotifier.value = ComposerBannerData(
      targetId: reply.id,
      title: 'Reply to $name',
      subtitle: _plainSnippet(reply.text),
      onTap: () => _scrollToReply(reply.id),
    );
    if (!_composerFocusNode.hasFocus) {
      _composerFocusNode.requestFocus();
    }
  }

  void _openUserProfile(int? authorId) {
    if (authorId == null) return;
    Navigator.pop(context);
    final currentUserId = Get.find<ServiceHandler>().profileData.value.id;
    if (authorId.toString() == currentUserId) {
      navigateWithSlide(() => const ProfilePage());
    } else {
      navigateWithSlide(() => UserProfilePage(userId: authorId));
    }
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
      backgroundColor: colors.surfaceContainerHighest,
      child: Icon(
        Icons.person_rounded,
        size: size * 0.55,
        color: colors.onSurfaceVariant,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isOled = _isDetailsOled(context);
    final sheetBg = isOled ? Colors.black : colors.surface;
    final screenHeight = MediaQuery.sizeOf(context).height;

    return WillPopScope(
      onWillPop: _confirmDiscard,
      child: Container(
        height: screenHeight * 0.92,
        decoration: BoxDecoration(
          color: sheetBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(
              color: colors.onSurface.opaque(0.08, iReallyMeanIt: true),
            ),
          ),
        ),
        child: Column(
          children: [
            // Handle + Threads-style Header Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.onSurfaceVariant
                            .opaque(0.3, iReallyMeanIt: true),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const AnymeXText(
                        'Activity',
                        size: 16,
                        variant: TextVariant.bold,
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 22),
                        onPressed: () async {
                          final discard = await _confirmDiscard();
                          if (discard && context.mounted) {
                            Navigator.pop(context);
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => FocusScope.of(context).unfocus(),
                      child: RepaintBoundary(
                        child: RefreshIndicator(
                          onRefresh: _fetchReplies,
                          child: CustomScrollView(
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics(),
                            ),
                            slivers: [
                              SliverToBoxAdapter(
                                child: ActivityCard(
                                  activity: widget.activity,
                                  onTap: () {},
                                  onReplyTap: () {
                                    _clearBanner();
                                    _composerFocusNode.requestFocus();
                                  },
                                ),
                              ),
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 6, 16, 6),
                                  child: AnymeXText(
                                    'Replies (${replies?.length ?? widget.activity.replyCount})',
                                    size: 14,
                                    variant: TextVariant.bold,
                                  ),
                                ),
                              ),
                              if (replies == null)
                                const SliverToBoxAdapter(
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(vertical: 40),
                                    child: Center(
                                        child: CircularProgressIndicator()),
                                  ),
                                )
                              else if (replies!.isEmpty)
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
                                          context.l10n.noRepliesYetBeTheFirst,
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
                                    margin: const EdgeInsets.fromLTRB(
                                        14, 6, 14, 120),
                                    decoration: BoxDecoration(
                                      color: isOled
                                          ? Colors.white.withValues(alpha: 0.03)
                                          : colors.surfaceContainer.opaque(
                                              0.35,
                                              iReallyMeanIt: true,
                                            ),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: colors.onSurface
                                            .opaque(0.08, iReallyMeanIt: true),
                                        width: 1,
                                      ),
                                    ),
                                    child: Padding(
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
                                              i < replies!.length;
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
                                            _buildReplyCard(replies![i]),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              if (replies == null || replies!.isEmpty)
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
                      defaultHint: 'Write a reply...',
                      customBannerNotifier: _bannerNotifier,
                      onClearStatusBanner: () =>
                          _clearBanner(clearTextIfEditing: true),
                      onSubmit: _postReply,
                      hasAuthToken: AnilistThreadsService.hasAnilistToken,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReplyCard(ActivityReply reply) {
    final colors = context.colors;
    final currentUserId =
        Get.find<AnilistAuth>().profileData.value.id.toString();
    final isOwn = reply.authorId?.toString() == currentUserId;
    final isTarget = _replyTargetId == reply.id;

    return RepaintBoundary(
      child: Container(
        key: _keyForReply(reply.id),
        padding: isTarget ? const EdgeInsets.all(8) : EdgeInsets.zero,
        decoration: isTarget
            ? BoxDecoration(
                color: colors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              )
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: [Avatar] nama_akun · date on left | [Reply icon] [Love] on right (matches Threads)
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _openUserProfile(reply.authorId),
                    child: Row(
                      children: [
                        _avatar(context, reply.authorAvatarUrl, size: 28),
                        const SizedBox(width: 8),
                        Flexible(
                          child: AnymeXText(
                            reply.authorName ?? 'User',
                            size: 13.5,
                            variant: TextVariant.bold,
                            color: colors.primary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (reply.timeAgo.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          AnymeXText(
                            '· ${reply.timeAgo}',
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
                Tooltip(
                  message: context.l10n.reply2,
                  child: InkWell(
                    canRequestFocus: false,
                    onTap: () => _replyToUser(reply),
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.all(5),
                      child: Icon(
                        Icons.reply_rounded,
                        size: 16,
                        color: isTarget
                            ? colors.primary
                            : colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                InkWell(
                  onTap: () => _toggleReplyLike(reply),
                  onLongPress: () => _showReplyLikedBySheet(context, reply),
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
                          reply.isLiked
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          size: 15,
                          color: reply.isLiked
                              ? colors.primary
                              : colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        AnymeXText(
                          '${reply.likeCount}',
                          size: 11.5,
                          variant: TextVariant.semiBold,
                          color: reply.isLiked
                              ? colors.primary
                              : colors.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
                if (isOwn) ...[
                  const SizedBox(width: 2),
                  InkWell(
                    onTap: () => _editReply(reply),
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.all(5),
                      child: Icon(
                        Icons.edit_outlined,
                        size: 15,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => _deleteReply(reply),
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
            // Row 2: Reply body aligned flush-left with avatar (matches Threads)
            const SizedBox(height: 6),
            AnilistAboutMe(about: reply.text),
          ],
        ),
      ),
    );
  }

  void _showReplyLikedBySheet(BuildContext context, ActivityReply reply) {
    if (reply.likes.isEmpty) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        final likeCount = reply.likes.length;
        final contentHeight = 70.0 + (likeCount * 90.0) + 16.0;
        final screenHeight = MediaQuery.sizeOf(sheetContext).height;
        final initialFraction = (contentHeight / screenHeight).clamp(0.25, 0.9);
        return DraggableScrollableSheet(
          initialChildSize: initialFraction,
          minChildSize: 0.25,
          maxChildSize: 0.9,
          expand: false,
          builder: (dragContext, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: dragContext.theme.colorScheme.surfaceContainer,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        const Icon(Icons.favorite, color: Colors.red, size: 20),
                        const SizedBox(width: 8),
                        AnymeXText(
                          context.l10n.likedBy,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: dragContext.theme.colorScheme.onSurface,
                          ),
                        ),
                        const Spacer(),
                        AnymeXText(
                          '${reply.likeCount}',
                          style: TextStyle(
                            fontSize: 14,
                            color:
                                dragContext.theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Divider(
                    height: 1,
                    color: dragContext.theme.colorScheme.outlineVariant
                        .withOpacity(0.3),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: reply.likes.length,
                      itemBuilder: (_, index) {
                        final liker = reply.likes[index];
                        return _buildLikerTile(dragContext, liker);
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildLikerTile(BuildContext context, ActivityLiker liker) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: GestureDetector(
        onTap: () {
          Navigator.of(context).pop();
          final currentUserId = Get.find<ServiceHandler>().profileData.value.id;
          if (liker.id.toString() == currentUserId) {
            navigate(() => const ProfilePage());
          } else {
            navigate(() => UserProfilePage(userId: liker.id));
          }
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 80,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (liker.bannerImage != null)
                  CachedNetworkImage(
                    imageUrl: liker.bannerImage!,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      color: context.theme.colorScheme.surfaceContainerHigh,
                    ),
                  )
                else
                  Container(
                    color: context.theme.colorScheme.surfaceContainerHigh,
                  ),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        context.theme.colorScheme.surfaceContainer
                            .withOpacity(0.95),
                        context.theme.colorScheme.surfaceContainer
                            .withOpacity(0.8),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      CommentumAvatar(
                        userId: liker.id.toString(),
                        avatarUrl: liker.avatarUrl,
                        size: 40,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: AnymeXText(
                          liker.name,
                          size: 16,
                          variant: TextVariant.bold,
                          color: context.theme.colorScheme.onSurface,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          isMarquee: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
