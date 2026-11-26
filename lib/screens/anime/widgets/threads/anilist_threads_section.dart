import 'dart:async';

import 'package:anymex/controllers/services/anilist/anilist_threads_service.dart';
import 'package:anymex/models/Anilist/anilist_thread.dart';
import 'package:anymex/models/Media/media.dart';
import 'package:anymex/controllers/settings/settings.dart';
import 'package:anymex/controllers/theme.dart';
import 'package:anymex/screens/anime/widgets/threads/anilist_create_thread_page.dart';
import 'package:anymex/screens/anime/widgets/threads/anilist_thread_detail_page.dart';
import 'package:get/get.dart';
import 'package:anymex/utils/function.dart';
import 'package:anymex/utils/theme_extensions.dart';
import 'package:anymex/widgets/anymex_widgets/anymex_container.dart';
import 'package:anymex/widgets/anymex_widgets/anymex_image.dart';
import 'package:anymex/widgets/anymex_widgets/anymex_text.dart';
import 'package:anymex/widgets/non_widgets/snackbar.dart';
import 'package:anymex_extension_runtime_bridge/Models/Source.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

enum _ThreadSortOption {
  recentActivity('Recent Activity', ['IS_STICKY', 'REPLIED_AT_DESC']),
  newest('Newest', ['IS_STICKY', 'ID_DESC']),
  mostReplied('Most Replied', ['IS_STICKY', 'REPLY_COUNT_DESC']),
  mostViewed('Most Viewed', ['IS_STICKY', 'VIEW_COUNT_DESC']);

  final String label;
  final List<String> gqlSort;
  const _ThreadSortOption(this.label, this.gqlSort);
}

class AnilistThreadsSection extends StatefulWidget {
  final Media media;

  const AnilistThreadsSection({
    super.key,
    required this.media,
  });

  @override
  State<AnilistThreadsSection> createState() => _AnilistThreadsSectionState();
}

class _AnilistThreadsSectionState extends State<AnilistThreadsSection> {
  int? _anilistMediaId;
  List<AnilistThread> _threads = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isLoadingMore = false;
  bool _hasNextPage = false;
  bool _mediaNotFound = false;
  int _page = 1;

  _ThreadSortOption _sort = _ThreadSortOption.recentActivity;
  bool _showSearch = false;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _loadThreads();
  }

  @override
  void didUpdateWidget(covariant AnilistThreadsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.media.id != widget.media.id ||
        oldWidget.media.idMal != widget.media.idMal) {
      _anilistMediaId = null;
      _loadThreads();
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadThreads({bool isRefresh = false}) async {
    if (mounted) {
      setState(() {
        if (isRefresh) {
          _isRefreshing = true;
        } else {
          _isLoading = true;
        }
        _mediaNotFound = false;
        _page = 1;
      });
    }

    final resolvedId = _anilistMediaId ??
        await AnilistThreadsService.resolveAnilistMediaId(widget.media);
    if (!mounted) return;

    if (resolvedId == null) {
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
        _mediaNotFound = true;
        _threads = [];
        _hasNextPage = false;
      });
      return;
    }

    _anilistMediaId = resolvedId;
    final (threads, hasNext) = await AnilistThreadsService.fetchMediaThreads(
      mediaId: resolvedId,
      page: 1,
      sort: _sort.gqlSort,
      search: _searchController.text,
    );

    if (!mounted) return;
    setState(() {
      _threads = threads;
      _hasNextPage = hasNext;
      _isLoading = false;
      _isRefreshing = false;
    });
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasNextPage || _anilistMediaId == null) return;
    setState(() => _isLoadingMore = true);
    final nextPage = _page + 1;
    final (more, hasNext) = await AnilistThreadsService.fetchMediaThreads(
      mediaId: _anilistMediaId!,
      page: nextPage,
      sort: _sort.gqlSort,
      search: _searchController.text,
    );
    if (!mounted) return;
    setState(() {
      _page = nextPage;
      _threads = [..._threads, ...more];
      _hasNextPage = hasNext;
      _isLoadingMore = false;
    });
  }

  void _openThread(AnilistThread thread) {
    final detailsTheme = Theme.of(context);
    navigate(
      () => AnilistThreadDetailPage(
        initialThread: thread,
        inheritedTheme: detailsTheme,
        onThreadUpdated: (updated) {
          if (!mounted) return;
          final idx = _threads.indexWhere((t) => t.id == updated.id);
          if (idx != -1) {
            setState(() => _threads[idx] = updated);
          }
        },
      ),
    );
  }

  bool _isOledDark(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (!isDark) return false;
    if (settingsController.detailsOledMode) return true;
    return Get.isRegistered<ThemeController>() &&
        Get.find<ThemeController>().isOled;
  }

  Future<void> _showCreateThreadSheet() async {
    if (!AnilistThreadsService.hasAnilistToken) {
      snackBar('Log in to AniList to create a thread');
      return;
    }
    if (_anilistMediaId == null) {
      errorSnackBar('AniList media ID not resolved yet');
      return;
    }

    final created = await AnilistCreateThreadPage.open(
      context,
      media: widget.media,
      anilistMediaId: _anilistMediaId!,
      inheritedTheme: Theme.of(context),
    );

    if (created != null && mounted) {
      successSnackBar('Thread created on AniList');
      setState(() {
        _threads = [created, ..._threads];
      });
      _openThread(created);
    }
  }

  String _relativeTime(int epochSeconds) {
    if (epochSeconds <= 0) return '';
    return formatTimeAgo(epochSeconds * 1000);
  }

  String _formatCount(int count) {
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}k';
    }
    return count.toString();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final media = widget.media;
    final String formatName = switch (media.mediaType) {
      ItemType.anime => 'Anime',
      ItemType.novel => 'Novel',
      _ => 'Manga',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _isOledDark(context)
                  ? Colors.white.withValues(alpha: 0.03)
                  : colors.surfaceContainer.opaque(0.35, iReallyMeanIt: true),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: colors.onSurface.opaque(0.08, iReallyMeanIt: true),
                width: 1,
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    if (media.poster.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: AnymeXImage(
                          imageUrl: media.poster,
                          width: 34,
                          height: 46,
                          fit: BoxFit.cover,
                        ),
                      )
                    else
                      AnymeXContainer(
                        width: 34,
                        height: 46,
                        color: colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                        child: Icon(
                          Icons.forum_outlined,
                          size: 20,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AnymeXText(
                            media.displayTitle.isNotEmpty
                                ? media.displayTitle
                                : 'AniList Threads',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            size: 15,
                            variant: TextVariant.bold,
                            color: colors.onSurface,
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              AnymeXContainer(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                color: colors.primary.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(4),
                                child: AnymeXText(
                                  'AniList · $formatName',
                                  size: 10,
                                  variant: TextVariant.bold,
                                  color: colors.primary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: AnymeXText(
                                  _isLoading
                                      ? 'Loading...'
                                      : '${_threads.length}${_hasNextPage ? '+' : ''} ${_threads.length == 1 ? 'thread' : 'threads'}',
                                  size: 12,
                                  color: colors.onSurfaceVariant,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        _showSearch ? Icons.close_rounded : Icons.search_rounded,
                        size: 20,
                        color: colors.onSurfaceVariant,
                      ),
                      tooltip: 'Search threads',
                      onPressed: () {
                        setState(() {
                          _showSearch = !_showSearch;
                          if (!_showSearch &&
                              _searchController.text.isNotEmpty) {
                            _searchController.clear();
                            _loadThreads(isRefresh: true);
                          }
                        });
                      },
                    ),
                    PopupMenuButton<_ThreadSortOption>(
                      onSelected: (option) {
                        if (option == _sort) return;
                        setState(() => _sort = option);
                        _loadThreads(isRefresh: true);
                      },
                      icon: Icon(
                        Icons.sort_rounded,
                        color: colors.onSurfaceVariant,
                      ),
                      tooltip: 'Sort threads',
                      itemBuilder: (_) => _ThreadSortOption.values
                          .map(
                            (opt) => PopupMenuItem(
                              value: opt,
                              child: Row(
                                children: [
                                  if (_sort == opt)
                                    Icon(Icons.check_rounded,
                                        size: 18, color: colors.primary)
                                  else
                                    const SizedBox(width: 18),
                                  const SizedBox(width: 8),
                                  Text(opt.label),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    if (AnilistThreadsService.hasAnilistToken &&
                        _anilistMediaId != null)
                      IconButton(
                        icon: const Icon(Icons.add_comment_outlined, size: 20),
                        tooltip: 'New thread',
                        onPressed: _showCreateThreadSheet,
                      ),
                    IconButton(
                      icon: _isRefreshing
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  colors.onSurfaceVariant,
                                ),
                              ),
                            )
                          : const Icon(Icons.refresh_rounded, size: 20),
                      tooltip: 'Refresh threads',
                      onPressed: _isRefreshing
                          ? null
                          : () => _loadThreads(isRefresh: true),
                    ),
                  ],
                ),
                if (_showSearch) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _searchController,
                    autofocus: true,
                    onChanged: (_) {
                      _searchDebounce?.cancel();
                      _searchDebounce = Timer(
                        const Duration(milliseconds: 450),
                        () => _loadThreads(isRefresh: true),
                      );
                    },
                    onSubmitted: (_) => _loadThreads(isRefresh: true),
                    decoration: InputDecoration(
                      hintText: 'Search AniList threads (e.g. Episode 7)...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      isDense: true,
                      filled: true,
                      fillColor: colors.surface.opaque(0.55, iReallyMeanIt: true),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_isLoading)
          _buildShimmer(context)
        else if (_mediaNotFound)
          _buildEmptyState(
            context,
            icon: Icons.link_off_rounded,
            title: 'No AniList entry matched',
            subtitle:
                'Could not find a matching AniList page to load forum threads for this title.',
          )
        else if (_threads.isEmpty)
          _buildEmptyState(
            context,
            icon: Icons.forum_outlined,
            title: _searchController.text.trim().isNotEmpty
                ? 'No matching threads found'
                : 'No AniList threads yet',
            subtitle: _searchController.text.trim().isNotEmpty
                ? 'Try a different keyword or clear the search filter.'
                : 'Be the first to start a discussion on AniList for this title.',
            showCreateButton: AnilistThreadsService.hasAnilistToken &&
                _searchController.text.trim().isEmpty,
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                for (final thread in _threads) _buildThreadCard(context, thread),
                if (_hasNextPage)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 14),
                    child: Center(
                      child: _isLoadingMore
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2.2),
                            )
                          : OutlinedButton.icon(
                              onPressed: _loadMore,
                              icon: const Icon(Icons.expand_more_rounded),
                              label: const Text('Load more threads'),
                            ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildThreadCard(BuildContext context, AnilistThread thread) {
    final colors = context.colors;
    final activityEpoch = thread.repliedAt ?? thread.createdAt;
    final activityUser = thread.replyUser ?? thread.user;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _isOledDark(context)
            ? Colors.white.withValues(alpha: 0.03)
            : colors.surfaceContainer.opaque(0.35, iReallyMeanIt: true),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: thread.isSticky
              ? colors.primary.withValues(alpha: 0.35)
              : colors.onSurface.opaque(0.08, iReallyMeanIt: true),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openThread(thread),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Row 1: Title on left | Views then Comments on right (no love)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: AnymeXText(
                        thread.title,
                        size: 14.5,
                        variant: TextVariant.bold,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.visibility_outlined,
                            size: 14,
                            color: colors.onSurfaceVariant,
                          ),
                          const SizedBox(width: 3),
                          AnymeXText(
                            _formatCount(thread.viewCount),
                            size: 11.5,
                            color: colors.onSurfaceVariant,
                          ),
                          const SizedBox(width: 10),
                          Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 14,
                            color: colors.onSurfaceVariant,
                          ),
                          const SizedBox(width: 3),
                          AnymeXText(
                            _formatCount(thread.replyCount),
                            size: 11.5,
                            color: colors.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                // Row 2: Thread categories below title
                if (thread.isSticky ||
                    thread.isLocked ||
                    thread.categories.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (thread.isSticky)
                        _chip(
                          context,
                          'Pinned',
                          icon: Icons.push_pin_rounded,
                          highlight: true,
                        ),
                      if (thread.isLocked)
                        _chip(
                          context,
                          'Locked',
                          icon: Icons.lock_outline_rounded,
                        ),
                      for (final cat in thread.categories.take(3))
                        if (cat.name.isNotEmpty) _chip(context, cat.name),
                    ],
                  ),
                ],
                // Row 3: Latest comment/reply below categories
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (activityUser?.avatarUrl?.isNotEmpty == true)
                      ClipOval(
                        child: AnymeXImage(
                          imageUrl: activityUser!.avatarUrl!,
                          width: 22,
                          height: 22,
                          radius: 11,
                          fit: BoxFit.cover,
                        ),
                      )
                    else
                      CircleAvatar(
                        radius: 11,
                        backgroundColor: colors.primary.withValues(alpha: 0.15),
                        child: Icon(Icons.person_rounded,
                            size: 13, color: colors.primary),
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AnymeXText(
                        thread.replyUser != null
                            ? '${thread.replyUser!.name} replied · ${_relativeTime(activityEpoch)}'
                            : '${thread.user?.name ?? 'Unknown'} · ${_relativeTime(activityEpoch)}',
                        size: 11.5,
                        color: colors.onSurfaceVariant,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(
    BuildContext context,
    String text, {
    IconData? icon,
    bool highlight = false,
  }) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: highlight
            ? colors.primary.withValues(alpha: 0.16)
            : colors.onSurface.opaque(0.07, iReallyMeanIt: true),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 11,
              color: highlight ? colors.primary : colors.onSurfaceVariant,
            ),
            const SizedBox(width: 3),
          ],
          AnymeXText(
            text,
            size: 10,
            variant: TextVariant.semiBold,
            color: highlight ? colors.primary : colors.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    bool showCreateButton = false,
  }) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 44),
      child: Center(
        child: Column(
          children: [
            Icon(
              icon,
              size: 40,
              color: colors.onSurfaceVariant.opaque(0.5, iReallyMeanIt: true),
            ),
            const SizedBox(height: 12),
            AnymeXText(
              title,
              size: 15,
              variant: TextVariant.bold,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            AnymeXText(
              subtitle,
              size: 12.5,
              color: colors.onSurfaceVariant,
              textAlign: TextAlign.center,
              maxLines: 3,
            ),
            if (showCreateButton) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _showCreateThreadSheet,
                icon: const Icon(Icons.add_comment_outlined, size: 18),
                label: const Text('Start a Thread'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildShimmer(BuildContext context) {
    final colors = context.colors;
    return Shimmer.fromColors(
      baseColor: colors.surfaceContainerHighest.opaque(0.25, iReallyMeanIt: true),
      highlightColor:
          colors.surfaceContainerHighest.opaque(0.45, iReallyMeanIt: true),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: List.generate(
            4,
            (_) => Container(
              height: 92,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
