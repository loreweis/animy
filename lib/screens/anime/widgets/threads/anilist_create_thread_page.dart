import 'package:anymex/controllers/services/anilist/anilist_threads_service.dart';
import 'package:anymex/controllers/theme.dart';
import 'package:anymex/models/Anilist/anilist_thread.dart';
import 'package:anymex/models/Media/media.dart';
import 'package:anymex/screens/anime/widgets/threads/anilist_thread_composer.dart';
import 'package:anymex/utils/al_about_me.dart';
import 'package:anymex/utils/markdown.dart';
import 'package:anymex/utils/theme_extensions.dart';
import 'package:anymex/widgets/anymex_widgets/anymex_text.dart';
import 'package:anymex/widgets/common/anymex_scaffold.dart';
import 'package:anymex/widgets/non_widgets/snackbar.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class _ThreadCategoryDef {
  final int id;
  final String name;
  const _ThreadCategoryDef(this.id, this.name);
}

class AnilistCreateThreadPage extends StatefulWidget {
  final Media media;
  final int anilistMediaId;

  const AnilistCreateThreadPage({
    super.key,
    required this.media,
    required this.anilistMediaId,
  });

  static Future<AnilistThread?> open(
    BuildContext context, {
    required Media media,
    required int anilistMediaId,
  }) {
    return Navigator.of(context).push<AnilistThread>(
      MaterialPageRoute(
        builder: (_) => AnilistCreateThreadPage(
          media: media,
          anilistMediaId: anilistMediaId,
        ),
      ),
    );
  }

  @override
  State<AnilistCreateThreadPage> createState() =>
      _AnilistCreateThreadPageState();
}

class _AnilistCreateThreadPageState extends State<AnilistCreateThreadPage> {
  static const List<_ThreadCategoryDef> _allCategories = [
    _ThreadCategoryDef(1, 'Anime'),
    _ThreadCategoryDef(2, 'Manga'),
    _ThreadCategoryDef(3, 'Light Novels'),
    _ThreadCategoryDef(4, 'Visual Novels'),
    _ThreadCategoryDef(5, 'Release Discussion'),
    _ThreadCategoryDef(15, 'Recommendations'),
    _ThreadCategoryDef(7, 'General'),
    _ThreadCategoryDef(8, 'News'),
    _ThreadCategoryDef(9, 'Music'),
    _ThreadCategoryDef(10, 'Gaming'),
    _ThreadCategoryDef(16, 'Forum Games'),
    _ThreadCategoryDef(11, 'Site Feedback'),
    _ThreadCategoryDef(12, 'Bug Reports'),
    _ThreadCategoryDef(18, 'AniList Apps'),
  ];

  // AniList forum category compatibility rules
  static const Set<int> _mediaTypeIds = {1, 2, 3, 4};
  static const Set<int> _exclusiveIds = {11, 12, 16, 18};
  static const int _releaseDiscussionId = 5;
  static const int _generalId = 7;

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();
  final FocusNode _bodyFocusNode = FocusNode();

  final Set<int> _selectedCategories = {};
  bool _isPreview = false;
  bool _isSubmitting = false;
  String? _categoryError;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _bodyFocusNode.dispose();
    super.dispose();
  }

  bool _isOledDark(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (!isDark) return false;
    return Get.isRegistered<ThemeController>() &&
        Get.find<ThemeController>().isOled;
  }

  /// Mirrors AniList's dynamic category hiding rules when certain categories
  /// are selected.
  List<_ThreadCategoryDef> get _visibleCategories {
    if (_selectedCategories.isEmpty) {
      return _allCategories;
    }

    // Selecting an exclusive category hides all other categories.
    final selectedExclusive =
        _selectedCategories.where(_exclusiveIds.contains).toList();
    if (selectedExclusive.isNotEmpty) {
      return _allCategories
          .where((c) => selectedExclusive.contains(c.id))
          .toList();
    }

    // Selecting Release Discussion hides everything except media-type categories.
    if (_selectedCategories.contains(_releaseDiscussionId)) {
      return _allCategories
          .where((c) =>
              c.id == _releaseDiscussionId || _mediaTypeIds.contains(c.id))
          .toList();
    }

    // Any non-exclusive category hides exclusive categories.
    // Non-media categories also hide Release Discussion.
    final hasNonMedia =
        _selectedCategories.any((id) => !_mediaTypeIds.contains(id));

    return _allCategories.where((c) {
      if (_exclusiveIds.contains(c.id)) return false;
      if (hasNonMedia && c.id == _releaseDiscussionId) return false;
      if (_selectedCategories.contains(_generalId) &&
          c.id == _releaseDiscussionId) {
        return false;
      }
      return true;
    }).toList();
  }

  void _toggleCategory(int id) {
    setState(() {
      if (_selectedCategories.contains(id)) {
        _selectedCategories.remove(id);
      } else {
        if (_exclusiveIds.contains(id)) {
          _selectedCategories
            ..clear()
            ..add(id);
        } else {
          if (_selectedCategories.length >= 2) {
            snackBar('You can select up to 2 categories');
            return;
          }
          _selectedCategories.add(id);
        }
      }
      if (_selectedCategories.isNotEmpty) {
        _categoryError = null;
      }
    });
  }

  Future<void> _submitThread() async {
    if (_isSubmitting) return;

    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();

    if (_selectedCategories.isEmpty) {
      setState(() {
        _categoryError = 'A thread category is required.';
      });
      snackBar('A thread category is required.');
      return;
    }

    if (title.isEmpty) {
      snackBar('Thread title cannot be empty');
      return;
    }

    if (body.isEmpty) {
      snackBar('Thread body cannot be empty');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _categoryError = null;
    });

    final created = await AnilistThreadsService.saveThread(
      title: title,
      body: body,
      mediaId: widget.anilistMediaId,
      categories: _selectedCategories.toList(),
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (created != null) {
      Navigator.of(context).pop(created);
    } else {
      errorSnackBar('Failed to create thread');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isOled = _isOledDark(context);
    final fieldBg = isOled
        ? Colors.white.withValues(alpha: 0.04)
        : colors.surfaceContainer.opaque(0.45, iReallyMeanIt: true);
    final borderCol = colors.onSurface.opaque(0.10, iReallyMeanIt: true);

    return AnymeXScaffold(
      body: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: isOled ? Colors.black : Colors.transparent,
          surfaceTintColor: Colors.transparent,
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AnymeXText(
                'New AniList Thread',
                size: 16,
                variant: TextVariant.bold,
              ),
              AnymeXText(
                widget.media.displayTitle,
                size: 11.5,
                color: colors.onSurfaceVariant,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: _isPreview ? 'Compose' : 'Preview',
              icon: Icon(
                _isPreview ? Icons.edit_rounded : Icons.preview_rounded,
                color: _isPreview ? colors.primary : colors.onSurfaceVariant,
              ),
              onPressed: () {
                setState(() => _isPreview = !_isPreview);
                if (_isPreview) {
                  _bodyFocusNode.unfocus();
                } else {
                  _bodyFocusNode.requestFocus();
                }
              },
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  // Title input
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: fieldBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: borderCol),
                    ),
                    child: TextField(
                      controller: _titleController,
                      textInputAction: TextInputAction.next,
                      style: TextStyle(
                        color: colors.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        filled: false,
                        fillColor: Colors.transparent,
                        isCollapsed: true,
                        contentPadding: EdgeInsets.zero,
                        hintText: 'Thread title',
                        hintStyle: TextStyle(
                          color: colors.onSurfaceVariant
                              .opaque(0.7, iReallyMeanIt: true),
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Categories section (required by AniList, dynamic hiding rules)
                  Row(
                    children: [
                      const AnymeXText(
                        'Categories',
                        size: 13,
                        variant: TextVariant.bold,
                      ),
                      const SizedBox(width: 6),
                      AnymeXText(
                        '(${_selectedCategories.length}/2)',
                        size: 11.5,
                        color: colors.onSurfaceVariant,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final cat in _visibleCategories)
                        _buildCategoryChip(context, cat),
                    ],
                  ),
                  if (_categoryError != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          size: 15,
                          color: colors.error,
                        ),
                        const SizedBox(width: 6),
                        AnymeXText(
                          _categoryError!,
                          size: 12,
                          variant: TextVariant.semiBold,
                          color: colors.error,
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),

                  // Body input / Preview
                  Container(
                    constraints: const BoxConstraints(minHeight: 190),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: fieldBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: borderCol),
                    ),
                    child: _isPreview
                        ? (_bodyController.text.trim().isEmpty
                            ? AnymeXText(
                                'Nothing to preview',
                                size: 14,
                                fontStyle: FontStyle.italic,
                                color: colors.onSurfaceVariant,
                              )
                            : AnilistAboutMe(
                                about: parseMarkdown(_bodyController.text),
                              ))
                        : TextField(
                            controller: _bodyController,
                            focusNode: _bodyFocusNode,
                            minLines: 7,
                            maxLines: null,
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            style: TextStyle(
                              color: colors.onSurface,
                              fontSize: 14.5,
                              height: 1.45,
                            ),
                            decoration: InputDecoration(
                              filled: false,
                              fillColor: Colors.transparent,
                              isCollapsed: true,
                              contentPadding: EdgeInsets.zero,
                              hintText: 'Write thread body',
                              hintStyle: TextStyle(
                                color: colors.onSurfaceVariant
                                    .opaque(0.7, iReallyMeanIt: true),
                                fontSize: 14.5,
                              ),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                            ),
                          ),
                  ),
                ],
              ),
            ),

            // Bottom bar: Markdown toolbar directly above Post Thread button
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                decoration: BoxDecoration(
                  color: isOled ? Colors.black : colors.surfaceContainer,
                  border: Border(
                    top: BorderSide(color: borderCol, width: 0.8),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!_isPreview) ...[
                      AnilistMarkdownToolbar(
                        controller: _bodyController,
                        focusNode: _bodyFocusNode,
                        onBeforeInsert: () {
                          if (_isPreview) {
                            setState(() => _isPreview = false);
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                    ],
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: FilledButton.icon(
                        onPressed: _isSubmitting ? null : _submitThread,
                        icon: _isSubmitting
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    colors.onPrimary,
                                  ),
                                ),
                              )
                            : const Icon(Icons.send_rounded, size: 18),
                        label: Text(
                          _isSubmitting ? 'Posting...' : 'Post Thread',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryChip(BuildContext context, _ThreadCategoryDef cat) {
    final colors = context.colors;
    final selected = _selectedCategories.contains(cat.id);
    return InkWell(
      onTap: () => _toggleCategory(cat.id),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? colors.primary.withValues(alpha: 0.18)
              : colors.onSurface.opaque(0.06, iReallyMeanIt: true),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? colors.primary
                : colors.onSurface.opaque(0.10, iReallyMeanIt: true),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Icon(Icons.check_rounded, size: 14, color: colors.primary),
              const SizedBox(width: 5),
            ],
            AnymeXText(
              cat.name,
              size: 12,
              variant: selected ? TextVariant.bold : TextVariant.semiBold,
              color: selected ? colors.primary : colors.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
