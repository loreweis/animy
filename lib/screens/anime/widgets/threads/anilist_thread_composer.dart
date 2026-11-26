import 'dart:ui';

import 'package:anymex/controllers/services/anilist/anilist_auth.dart';
import 'package:anymex/controllers/settings/settings.dart';
import 'package:anymex/controllers/theme.dart';
import 'package:anymex/models/Anilist/anilist_thread.dart';
import 'package:anymex/screens/anime/widgets/comments/widgets/gif_picker_sheet.dart';
import 'package:anymex/utils/theme_extensions.dart';
import 'package:anymex/widgets/anymex_widgets/anymex_image.dart';
import 'package:anymex/widgets/anymex_widgets/anymex_text.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

bool _isAppOledDark(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  if (!isDark) return false;
  if (settingsController.detailsOledMode) return true;
  if (Get.isRegistered<ThemeController>()) {
    return Get.find<ThemeController>().isOled;
  }
  return false;
}

/// Shared AniList Smart URL detector & Markdown toolbar used by both
/// [AnilistThreadComposer] and [AnilistCreateThreadPage].
class AnilistMarkdownToolbar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final VoidCallback? onBeforeInsert;

  const AnilistMarkdownToolbar({
    super.key,
    required this.controller,
    this.focusNode,
    this.onBeforeInsert,
  });

  static String detectUrlKind(String raw) {
    final url = raw.trim();
    if (url.isEmpty) return 'link';
    final uri = Uri.tryParse(url);
    final host = (uri?.host ?? '').toLowerCase();
    final path = (uri?.path ?? url).toLowerCase();

    if (host.contains('youtube.com') ||
        host == 'youtu.be' ||
        host.endsWith('.youtu.be')) {
      return 'youtube';
    }
    if (RegExp(r'\.(webm|mp4|mov|m4v|ogv)$', caseSensitive: false)
        .hasMatch(path)) {
      return 'webm';
    }
    if (RegExp(r'\.(png|jpe?g|gif|webp|avif|bmp|svg)$', caseSensitive: false)
            .hasMatch(path) ||
        host == 'i.imgur.com' ||
        host.contains('giphy.com') ||
        host.contains('tenor.com') ||
        (host.contains('anilist.co') && path.contains('/file/'))) {
      return 'image';
    }
    return 'link';
  }

  static void wrapSelection(
    TextEditingController controller,
    String before,
    String after,
    String placeholder, {
    FocusNode? focusNode,
  }) {
    final text = controller.text;
    final sel = controller.selection;
    final hasValidSel = sel.start >= 0 && sel.end >= sel.start;
    final start = hasValidSel ? sel.start : text.length;
    final end = hasValidSel ? sel.end : text.length;

    final selected = start < end ? text.substring(start, end) : placeholder;
    final replacement = '$before$selected$after';
    final updated = text.replaceRange(start, end, replacement);

    controller.value = TextEditingValue(
      text: updated,
      selection: TextSelection(
        baseOffset: start + before.length,
        extentOffset: start + before.length + selected.length,
      ),
    );
    focusNode?.requestFocus();
  }

  static void insertLinePrefix(
    TextEditingController controller,
    String prefix,
    String placeholder, {
    FocusNode? focusNode,
  }) {
    final text = controller.text;
    final sel = controller.selection;
    final hasValidSel = sel.start >= 0 && sel.end >= sel.start;
    final start = hasValidSel ? sel.start : text.length;
    final end = hasValidSel ? sel.end : text.length;

    if (start < end) {
      final selected = text.substring(start, end);
      final formatted = selected
          .split('\n')
          .map((line) => line.trim().isEmpty ? line : '$prefix$line')
          .join('\n');
      final updated = text.replaceRange(start, end, formatted);
      controller.value = TextEditingValue(
        text: updated,
        selection: TextSelection(
          baseOffset: start,
          extentOffset: start + formatted.length,
        ),
      );
    } else {
      final needsNewline = start > 0 && text[start - 1] != '\n';
      final lead = needsNewline ? '\n$prefix' : prefix;
      final replacement = '$lead$placeholder';
      final updated = text.replaceRange(start, end, replacement);
      controller.value = TextEditingValue(
        text: updated,
        selection: TextSelection(
          baseOffset: start + lead.length,
          extentOffset: start + lead.length + placeholder.length,
        ),
      );
    }
    focusNode?.requestFocus();
  }

  static void insertRaw(
    TextEditingController controller,
    String snippet, {
    FocusNode? focusNode,
  }) {
    final text = controller.text;
    final sel = controller.selection;
    final hasValidSel = sel.start >= 0 && sel.end >= sel.start;
    final start = hasValidSel ? sel.start : text.length;
    final end = hasValidSel ? sel.end : text.length;
    final beforeCursor = text.substring(0, start);
    final prefix = beforeCursor.isNotEmpty &&
            !beforeCursor.endsWith(' ') &&
            !beforeCursor.endsWith('\n')
        ? '\n'
        : '';
    final insertion = '$prefix$snippet';
    final updated = text.replaceRange(start, end, insertion);
    controller.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: start + insertion.length),
    );
    focusNode?.requestFocus();
  }

  static Future<void> showSmartUrlDialog(
    BuildContext context, {
    required TextEditingController controller,
    FocusNode? focusNode,
    VoidCallback? onBeforeInsert,
  }) async {
    final urlCtrl = TextEditingController();
    final isOled = _isAppOledDark(context);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final colors = ctx.colors;
            final current = urlCtrl.text.trim();
            final kind = detectUrlKind(current);
            final (label, icon) = switch (kind) {
              'youtube' => ('YouTube · youtube(...)', Icons.smart_display_rounded),
              'webm' => ('Video · webm(...)', Icons.videocam_rounded),
              'image' => ('Image · img(...)', Icons.image_outlined),
              _ => ('Link · [text](...)', Icons.link_rounded),
            };

            return AlertDialog(
              backgroundColor:
                  isOled ? const Color(0xFF0E0E10) : colors.surfaceContainer,
              title: const AnymeXText(
                'Insert URL',
                size: 16,
                variant: TextVariant.bold,
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: urlCtrl,
                    autofocus: true,
                    keyboardType: TextInputType.url,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Paste link, image, YouTube, or WebM URL...',
                      filled: true,
                      fillColor:
                          colors.onSurface.opaque(0.06, iReallyMeanIt: true),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (val) => Navigator.of(ctx).pop(val.trim()),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: current.isEmpty
                          ? colors.onSurface.opaque(0.06, iReallyMeanIt: true)
                          : colors.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          icon,
                          size: 14,
                          color: current.isEmpty
                              ? colors.onSurfaceVariant
                              : colors.primary,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: AnymeXText(
                            current.isEmpty
                                ? 'Auto-detects Link, Image, YouTube & WebM'
                                : 'Detected: $label',
                            size: 11.5,
                            variant: TextVariant.semiBold,
                            color: current.isEmpty
                                ? colors.onSurfaceVariant
                                : colors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(urlCtrl.text.trim()),
                  child: const Text('Insert'),
                ),
              ],
            );
          },
        );
      },
    );
    urlCtrl.dispose();

    if (result == null || result.isEmpty) return;

    onBeforeInsert?.call();
    final normalized = result.contains('://') ? result : 'https://$result';
    switch (detectUrlKind(normalized)) {
      case 'youtube':
        insertRaw(controller, 'youtube($normalized)', focusNode: focusNode);
        break;
      case 'webm':
        insertRaw(controller, 'webm($normalized)', focusNode: focusNode);
        break;
      case 'image':
        insertRaw(controller, 'img($normalized)', focusNode: focusNode);
        break;
      default:
        wrapSelection(controller, '[', ']($normalized)', 'link text',
            focusNode: focusNode);
        break;
    }
  }

  static void openGifPicker(
    BuildContext context, {
    required TextEditingController controller,
    FocusNode? focusNode,
    VoidCallback? onBeforeInsert,
  }) {
    onBeforeInsert?.call();
    GifPickerSheet.show(
      context,
      onGifSelected: (gifUrl) {
        final clean = gifUrl.trim();
        if (clean.isEmpty) return;
        insertRaw(controller, 'img($clean)', focusNode: focusNode);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tools = <({IconData icon, String tip, VoidCallback onTap})>[
      (
        icon: Icons.format_bold,
        tip: 'Bold',
        onTap: () {
          onBeforeInsert?.call();
          wrapSelection(controller, '**', '**', 'bold', focusNode: focusNode);
        },
      ),
      (
        icon: Icons.format_italic,
        tip: 'Italic',
        onTap: () {
          onBeforeInsert?.call();
          wrapSelection(controller, '*', '*', 'italic', focusNode: focusNode);
        },
      ),
      (
        icon: Icons.format_strikethrough,
        tip: 'Strikethrough',
        onTap: () {
          onBeforeInsert?.call();
          wrapSelection(controller, '~~', '~~', 'strikethrough',
              focusNode: focusNode);
        },
      ),
      (
        icon: Icons.visibility_off_outlined,
        tip: 'Spoiler',
        onTap: () {
          onBeforeInsert?.call();
          wrapSelection(controller, '~!', '!~', 'spoiler',
              focusNode: focusNode);
        },
      ),
      (
        icon: Icons.code,
        tip: 'Inline Code',
        onTap: () {
          onBeforeInsert?.call();
          wrapSelection(controller, '`', '`', 'code', focusNode: focusNode);
        },
      ),
      (
        icon: Icons.data_object,
        tip: 'Code Block',
        onTap: () {
          onBeforeInsert?.call();
          wrapSelection(controller, '```\n', '\n```', 'code block',
              focusNode: focusNode);
        },
      ),
      (
        icon: Icons.add_link,
        tip: 'Insert URL (Link / Image / YouTube / WebM)',
        onTap: () => showSmartUrlDialog(
          context,
          controller: controller,
          focusNode: focusNode,
          onBeforeInsert: onBeforeInsert,
        ),
      ),
      (
        icon: Icons.gif_box_outlined,
        tip: 'Insert GIF',
        onTap: () => openGifPicker(
          context,
          controller: controller,
          focusNode: focusNode,
          onBeforeInsert: onBeforeInsert,
        ),
      ),
      (
        icon: Icons.format_quote,
        tip: 'Quote',
        onTap: () {
          onBeforeInsert?.call();
          insertLinePrefix(controller, '> ', 'quote', focusNode: focusNode);
        },
      ),
      (
        icon: Icons.format_list_bulleted,
        tip: 'Bullet List',
        onTap: () {
          onBeforeInsert?.call();
          insertLinePrefix(controller, '- ', 'list item', focusNode: focusNode);
        },
      ),
      (
        icon: Icons.format_list_numbered,
        tip: 'Numbered List',
        onTap: () {
          onBeforeInsert?.call();
          insertLinePrefix(controller, '1. ', 'list item',
              focusNode: focusNode);
        },
      ),
      (
        icon: Icons.title,
        tip: 'Header',
        onTap: () {
          onBeforeInsert?.call();
          insertLinePrefix(controller, '## ', 'Heading', focusNode: focusNode);
        },
      ),
      (
        icon: Icons.format_align_center,
        tip: 'Center',
        onTap: () {
          onBeforeInsert?.call();
          wrapSelection(controller, '~~~', '~~~', 'centered',
              focusNode: focusNode);
        },
      ),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: tools.map((tool) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Tooltip(
              message: tool.tip,
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  canRequestFocus: false,
                  customBorder: const CircleBorder(),
                  onTap: tool.onTap,
                  child: SizedBox(
                    width: 38,
                    height: 38,
                    child: Center(
                      child: Icon(
                        tool.icon,
                        size: 20,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// 2-layer Floating Pill Comment Composer matching the user's reference layout:
/// - LAYER 1: Floating full-pill chat bar (Avatar left, Input/Preview center,
///   borderless Preview/Compose + circular Send button inside right when text exists)
/// - LAYER 2: Separate MD-style bottom sheet that appears ONLY when focused
///   and collapses automatically when keyboard is dismissed or unfocused.
class AnilistThreadComposer extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueNotifier<AnilistThreadComment?> replyingToNotifier;
  final Future<bool> Function(String text, int? parentCommentId) onSubmit;
  final bool isLocked;
  final bool hasAuthToken;

  const AnilistThreadComposer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.replyingToNotifier,
    required this.onSubmit,
    required this.isLocked,
    required this.hasAuthToken,
  });

  @override
  State<AnilistThreadComposer> createState() => _AnilistThreadComposerState();
}

class _AnilistThreadComposerState extends State<AnilistThreadComposer>
    with WidgetsBindingObserver {
  bool _hasFocus = false;
  bool _hasText = false;
  bool _isPreview = false;
  bool _isSending = false;
  bool _wasKeyboardVisible = false;
  final Set<int> _revealedSpoilers = <int>{};
  String? _avatarUrl;

  bool get _showToolbar => _hasFocus && !_isPreview;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _avatarUrl = _resolveAvatarUrl();
    _hasFocus = widget.focusNode.hasFocus;
    _hasText = widget.controller.text.trim().isNotEmpty;
    widget.focusNode.addListener(_onFocusChange);
    widget.controller.addListener(_onTextChange);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.focusNode.removeListener(_onFocusChange);
    widget.controller.removeListener(_onTextChange);
    super.dispose();
  }

  String? _resolveAvatarUrl() {
    if (!Get.isRegistered<AnilistAuth>()) return null;
    final url = Get.find<AnilistAuth>().profileData.value.avatar;
    if (url == null || url.trim().isEmpty) return null;
    return url.trim();
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final view = View.maybeOf(context);
    if (view == null) return;

    final bottomInset = view.viewInsets.bottom;
    final isKeyboardVisible = bottomInset > 0;

    if (_wasKeyboardVisible && !isKeyboardVisible && widget.focusNode.hasFocus) {
      widget.focusNode.unfocus();
    }
    _wasKeyboardVisible = isKeyboardVisible;
  }

  void _onFocusChange() {
    final focused = widget.focusNode.hasFocus;
    if (focused != _hasFocus && mounted) {
      setState(() => _hasFocus = focused);
    }
  }

  void _onTextChange() {
    final hasText = widget.controller.text.trim().isNotEmpty;
    if (hasText != _hasText && mounted) {
      setState(() {
        _hasText = hasText;
        if (!hasText && _isPreview) {
          _isPreview = false;
        }
      });
    }
  }

  void _togglePreview() {
    setState(() {
      _isPreview = !_isPreview;
      _revealedSpoilers.clear();
    });

    if (_isPreview) {
      widget.focusNode.unfocus();
    } else {
      widget.focusNode.requestFocus();
    }
  }

  Future<void> _handleSend() async {
    final text = widget.controller.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    final ok = await widget.onSubmit(text, widget.replyingToNotifier.value?.id);
    if (!mounted) return;

    setState(() => _isSending = false);
    if (ok) {
      widget.controller.clear();
      widget.replyingToNotifier.value = null;
      setState(() {
        _isPreview = false;
        _revealedSpoilers.clear();
      });
      widget.focusNode.unfocus();
    }
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

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isOled = _isAppOledDark(context);
    final bottomSafe = MediaQuery.paddingOf(context).bottom;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final keyboardOpen = keyboardInset > 0;

    if (widget.isLocked || !widget.hasAuthToken) {
      return RepaintBoundary(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            12,
            0,
            12,
            bottomSafe + 12,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isOled
                      ? Colors.black
                      : colors.surfaceContainer.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: colors.onSurface.opaque(0.10, iReallyMeanIt: true),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      widget.isLocked
                          ? Icons.lock_outline_rounded
                          : Icons.login_rounded,
                      size: 16,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: AnymeXText(
                        widget.isLocked
                            ? 'This thread is locked'
                            : 'Log in to AniList to comment',
                        size: 13,
                        color: colors.onSurfaceVariant,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return RepaintBoundary(
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboardInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Replying-to compact banner above the pill when replying to a comment
            ValueListenableBuilder<AnilistThreadComment?>(
              valueListenable: widget.replyingToNotifier,
              builder: (context, replyingTo, _) {
                if (replyingTo == null) return const SizedBox.shrink();
                final snippet = _plainSnippet(replyingTo.commentHtml);
                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
                      decoration: BoxDecoration(
                        color: isOled
                            ? const Color(0xFF101014)
                            : colors.surfaceContainer.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: colors.primary.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.subdirectory_arrow_right_rounded,
                            size: 16,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AnymeXText(
                                  'Replying to @${replyingTo.user?.name ?? 'comment'}',
                                  size: 11.5,
                                  variant: TextVariant.bold,
                                  color: colors.primary,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (snippet.isNotEmpty)
                                  AnymeXText(
                                    snippet,
                                    size: 11,
                                    color: colors.onSurfaceVariant,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                          InkWell(
                            canRequestFocus: false,
                            onTap: () => widget.replyingToNotifier.value = null,
                            borderRadius: BorderRadius.circular(14),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                Icons.close_rounded,
                                size: 16,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),

            // LAYER 1: Floating Full-Pill Chat Bar (Home-bar glass/OLED styling)
            Padding(
              padding: EdgeInsets.fromLTRB(
                12,
                0,
                12,
                _showToolbar ? 10 : (keyboardOpen ? 10 : bottomSafe + 12),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: _buildPillShell(
                  colors: colors,
                  isOled: isOled,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _buildAvatar(colors, isOled),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: _isPreview
                              ? _buildPreview(colors)
                              : _buildTextField(colors),
                        ),
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        child: _hasText
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(width: 4),
                                  _buildPreviewToggleButton(colors),
                                  const SizedBox(width: 4),
                                  _buildSendButton(colors),
                                ],
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // LAYER 2: Separate MD-Style Bottom Sheet (only visible when focused & not previewing)
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _showToolbar
                  ? _buildMarkdownSheet(
                      colors,
                      isOled,
                      keyboardOpen ? 0 : bottomSafe,
                    )
                  : const SizedBox(width: double.infinity, height: 0),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPillShell({
    required ColorScheme colors,
    required bool isOled,
    required Widget child,
  }) {
    final radius = BorderRadius.circular(24);
    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(
          color: colors.onSurface.opaque(0.12, iReallyMeanIt: true),
          width: 0.9,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.opaque(0.22, iReallyMeanIt: true),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Obx(() {
          final isTranslucent = settingsController.transculentBar;
          final bgColor = isOled
              ? (isTranslucent
                  ? Colors.black.withValues(alpha: 0.72)
                  : Colors.black)
              : (isTranslucent
                  ? colors.surfaceContainer.withValues(alpha: 0.45)
                  : colors.surfaceContainer.withValues(alpha: 0.96));

          final inner = Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: radius,
            ),
            child: child,
          );

          if (!isTranslucent) return inner;
          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: inner,
          );
        }),
      ),
    );
  }

  Widget _buildAvatar(ColorScheme colors, bool isOled) {
    final url = _avatarUrl;
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: isOled
            ? const Color(0xFF141418)
            : colors.onSurface.opaque(0.08, iReallyMeanIt: true),
        shape: BoxShape.circle,
        border: Border.all(
          color: colors.onSurface.opaque(0.14, iReallyMeanIt: true),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: url != null
          ? AnymeXImage(
              imageUrl: url,
              width: 34,
              height: 34,
              radius: 17,
              fit: BoxFit.cover,
            )
          : Center(
              child: Icon(
                Icons.person_rounded,
                size: 18,
                color: colors.onSurfaceVariant,
              ),
            ),
    );
  }

  Widget _buildTextField(ColorScheme colors) {
    return ValueListenableBuilder<AnilistThreadComment?>(
      valueListenable: widget.replyingToNotifier,
      builder: (context, replyingTo, _) {
        return TextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          minLines: 1,
          maxLines: 6,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          cursorColor: colors.primary,
          style: TextStyle(
            color: colors.onSurface,
            fontSize: 15,
            height: 1.35,
          ),
          decoration: InputDecoration(
            filled: false,
            fillColor: Colors.transparent,
            isCollapsed: true,
            contentPadding: EdgeInsets.zero,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            hintText:
                replyingTo != null ? 'Write a reply...' : 'Write a comment...',
            hintStyle: TextStyle(
              color: colors.onSurfaceVariant.opaque(0.7, iReallyMeanIt: true),
              fontSize: 15,
            ),
          ),
        );
      },
    );
  }

  Widget _buildPreview(ColorScheme colors) {
    final text = widget.controller.text;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 160),
      child: SingleChildScrollView(
        child: text.trim().isEmpty
            ? Text(
                'Nothing to preview',
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontSize: 15,
                  fontStyle: FontStyle.italic,
                ),
              )
            : _buildMarkdownRichText(text, colors),
      ),
    );
  }

  Widget _buildPreviewToggleButton(ColorScheme colors) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        canRequestFocus: false,
        onTap: _togglePreview,
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          width: 34,
          height: 34,
          child: Center(
            child: Icon(
              _isPreview ? Icons.edit_outlined : Icons.preview_outlined,
              size: 20,
              color: _isPreview ? colors.primary : colors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSendButton(ColorScheme colors) {
    return Material(
      color: colors.primary,
      shape: const CircleBorder(),
      child: InkWell(
        canRequestFocus: false,
        onTap: _isSending ? null : _handleSend,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 34,
          height: 34,
          child: Center(
            child: _isSending
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(colors.onPrimary),
                    ),
                  )
                : Icon(
                    Icons.send_rounded,
                    size: 17,
                    color: colors.onPrimary,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildMarkdownSheet(
    ColorScheme colors,
    bool isOled,
    double bottomSafe,
  ) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isOled ? Colors.black : colors.surfaceContainer,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(
            color: colors.onSurface.opaque(0.10, iReallyMeanIt: true),
          ),
        ),
      ),
      padding: EdgeInsets.fromLTRB(12, 10, 12, 10 + bottomSafe),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: AnilistMarkdownToolbar(
            controller: widget.controller,
            focusNode: widget.focusNode,
            onBeforeInsert: () {
              if (_isPreview) {
                setState(() => _isPreview = false);
              }
            },
          ),
        ),
      ),
    );
  }

  /// Lightweight built-in AniList Markdown preview (zero HtmlWidget lag),
  /// supports bold, italic, strikethrough, inline code, links, headings,
  /// quotes, center `~~~`, img(...) preview, and tap-to-reveal `~!...!~` spoilers.
  Widget _buildMarkdownRichText(String raw, ColorScheme colors) {
    final lines = raw.split('\n');
    int spoilerCounter = 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: lines.map((line) {
        String content = line;
        TextAlign align = TextAlign.start;
        TextStyle baseStyle = TextStyle(
          color: colors.onSurface,
          fontSize: 15,
          height: 1.4,
        );
        bool isQuote = false;

        final trimmed = content.trim();
        final centerMatch =
            RegExp(r'^~~~([\s\S]*)~~~$').firstMatch(trimmed) ??
                RegExp(r'^<center>([\s\S]*)</center>$').firstMatch(trimmed);
        if (centerMatch != null) {
          align = TextAlign.center;
          content = centerMatch.group(1) ?? '';
        }

        final imgOnly =
            RegExp(r'^img\((https?:\/\/[^\s)]+)\)$', caseSensitive: false)
                .firstMatch(trimmed);
        if (imgOnly != null) {
          final url = imgOnly.group(1)!;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AnymeXImage(
                imageUrl: url,
                height: 110,
                width: 180,
                radius: 10,
                fit: BoxFit.cover,
              ),
            ),
          );
        }

        if (content.startsWith('## ')) {
          content = content.substring(3);
          baseStyle = baseStyle.copyWith(
            fontSize: 17,
            fontWeight: FontWeight.w700,
          );
        } else if (content.startsWith('# ')) {
          content = content.substring(2);
          baseStyle = baseStyle.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w700,
          );
        } else if (content.startsWith('> ')) {
          content = content.substring(2);
          isQuote = true;
          baseStyle = baseStyle.copyWith(color: colors.onSurfaceVariant);
        } else if (content.startsWith('- ')) {
          content = '• ${content.substring(2)}';
        }

        final spans = _parseInlineMarkdown(
          content,
          baseStyle,
          colors,
          () => spoilerCounter++,
        );

        final textWidget = RichText(
          textAlign: align,
          text: TextSpan(style: baseStyle, children: spans),
        );

        if (isQuote) {
          return Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.only(left: 10),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: colors.primary, width: 3),
              ),
            ),
            child: textWidget,
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: textWidget,
        );
      }).toList(),
    );
  }

  List<InlineSpan> _parseInlineMarkdown(
    String input,
    TextStyle baseStyle,
    ColorScheme colors,
    int Function() nextSpoilerId,
  ) {
    final pattern = RegExp(
      r'(\*\*(.+?)\*\*|\*(.+?)\*|~~(.+?)~~|`([^`]+)`|~!(.+?)!~|\|\|(.+?)\|\||\[([^\]]+)\]\((https?:\/\/[^\s)]+)\))',
    );

    final spans = <InlineSpan>[];
    int lastEnd = 0;

    for (final match in pattern.allMatches(input)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: input.substring(lastEnd, match.start)));
      }

      if (match.group(2) != null) {
        spans.add(TextSpan(
          text: match.group(2),
          style: baseStyle.copyWith(fontWeight: FontWeight.w700),
        ));
      } else if (match.group(3) != null) {
        spans.add(TextSpan(
          text: match.group(3),
          style: baseStyle.copyWith(fontStyle: FontStyle.italic),
        ));
      } else if (match.group(4) != null) {
        spans.add(TextSpan(
          text: match.group(4),
          style: baseStyle.copyWith(decoration: TextDecoration.lineThrough),
        ));
      } else if (match.group(5) != null) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: colors.onSurface.opaque(0.10, iReallyMeanIt: true),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              match.group(5)!,
              style: baseStyle.copyWith(
                fontFamily: 'monospace',
                fontSize: 13,
              ),
            ),
          ),
        ));
      } else if (match.group(6) != null || match.group(7) != null) {
        final spoilerText = match.group(6) ?? match.group(7)!;
        final id = nextSpoilerId();
        final revealed = _revealedSpoilers.contains(id);
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: GestureDetector(
            onTap: () {
              setState(() {
                if (revealed) {
                  _revealedSpoilers.remove(id);
                } else {
                  _revealedSpoilers.add(id);
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: revealed
                    ? colors.primary.withValues(alpha: 0.16)
                    : colors.onSurface.opaque(0.22, iReallyMeanIt: true),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                spoilerText,
                style: baseStyle.copyWith(
                  color: revealed ? baseStyle.color : Colors.transparent,
                ),
              ),
            ),
          ),
        ));
      } else if (match.group(8) != null) {
        spans.add(TextSpan(
          text: match.group(8),
          style: baseStyle.copyWith(
            color: colors.primary,
            decoration: TextDecoration.underline,
            decorationColor: colors.primary,
          ),
        ));
      }

      lastEnd = match.end;
    }

    if (lastEnd < input.length) {
      spans.add(TextSpan(text: input.substring(lastEnd)));
    }

    return spans;
  }
}
