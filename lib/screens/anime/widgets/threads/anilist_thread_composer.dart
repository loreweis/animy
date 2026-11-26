import 'dart:ui';

import 'package:anymex/controllers/services/anilist/anilist_auth.dart';
import 'package:anymex/controllers/settings/methods.dart';
import 'package:anymex/controllers/settings/settings.dart';
import 'package:anymex/controllers/theme.dart';
import 'package:anymex/models/Anilist/anilist_thread.dart';
import 'package:anymex/screens/anime/widgets/comments/widgets/gif_picker_sheet.dart';
import 'package:anymex/utils/al_about_me.dart';
import 'package:anymex/utils/markdown.dart';
import 'package:anymex/utils/theme_extensions.dart';
import 'package:anymex/widgets/anymex_widgets/anymex_image.dart';
import 'package:anymex/widgets/anymex_widgets/anymex_text.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

bool _isAppOledDark(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  if (!isDark) return false;
  if (Get.isRegistered<ThemeController>()) {
    return Get.find<ThemeController>().isOled;
  }
  return false;
}

/// Reusable scrollable AniList Markdown toolbar with Smart Insert URL
/// (auto-detects Link, Image, YouTube, WebM) and plain GIF button.
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

  void _wrapSelection(String before, String after, String placeholder) {
    onBeforeInsert?.call();
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

  void _insertLinePrefix(String prefix, String placeholder) {
    onBeforeInsert?.call();
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

  void _insertRaw(String snippet) {
    onBeforeInsert?.call();
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

  Future<void> _insertSmartUrl(BuildContext context) async {
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
                      fillColor: colors.onSurface
                          .opaque(0.06, iReallyMeanIt: true),
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

    final normalized = result.contains('://') ? result : 'https://$result';
    switch (detectUrlKind(normalized)) {
      case 'youtube':
        _insertRaw('youtube($normalized)');
        break;
      case 'webm':
        _insertRaw('webm($normalized)');
        break;
      case 'image':
        _insertRaw('img($normalized)');
        break;
      default:
        _wrapSelection('[', ']($normalized)', 'link text');
        break;
    }
  }

  void _openGifPicker(BuildContext context) {
    onBeforeInsert?.call();
    GifPickerSheet.show(
      context,
      onGifSelected: (gifUrl) {
        final clean = gifUrl.trim();
        if (clean.isEmpty) return;
        _insertRaw('img($clean)');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Row(
          children: [
            _mdBtn(
              context,
              icon: Icons.format_bold_rounded,
              tooltip: 'Bold',
              onTap: () => _wrapSelection('**', '**', 'bold text'),
            ),
            _mdBtn(
              context,
              icon: Icons.format_italic_rounded,
              tooltip: 'Italic',
              onTap: () => _wrapSelection('*', '*', 'italic text'),
            ),
            _mdBtn(
              context,
              icon: Icons.format_strikethrough_rounded,
              tooltip: 'Strikethrough',
              onTap: () => _wrapSelection('~~', '~~', 'strikethrough'),
            ),
            _mdBtn(
              context,
              icon: Icons.visibility_off_rounded,
              tooltip: 'Spoiler',
              onTap: () => _wrapSelection('~!', '!~', 'spoiler'),
            ),
            _mdBtn(
              context,
              icon: Icons.code_rounded,
              tooltip: 'Inline Code',
              onTap: () => _wrapSelection('`', '`', 'code'),
            ),
            _mdBtn(
              context,
              icon: Icons.integration_instructions_rounded,
              tooltip: 'Code Block',
              onTap: () => _wrapSelection('```\n', '\n```', 'code block'),
            ),
            _mdBtn(
              context,
              icon: Icons.add_link_rounded,
              tooltip: 'Insert URL (Link / Image / YouTube / WebM)',
              onTap: () => _insertSmartUrl(context),
            ),
            _mdBtn(
              context,
              icon: Icons.gif_box_outlined,
              tooltip: 'Insert GIF',
              onTap: () => _openGifPicker(context),
            ),
            _mdBtn(
              context,
              icon: Icons.format_quote_rounded,
              tooltip: 'Quote',
              onTap: () => _insertLinePrefix('> ', 'quote'),
            ),
            _mdBtn(
              context,
              icon: Icons.format_list_bulleted_rounded,
              tooltip: 'Bullet List',
              onTap: () => _insertLinePrefix('- ', 'list item'),
            ),
            _mdBtn(
              context,
              icon: Icons.format_list_numbered_rounded,
              tooltip: 'Numbered List',
              onTap: () => _insertLinePrefix('1. ', 'list item'),
            ),
            _mdBtn(
              context,
              icon: Icons.title_rounded,
              tooltip: 'Header',
              onTap: () => _insertLinePrefix('# ', 'heading'),
            ),
            _mdBtn(
              context,
              icon: Icons.format_align_center_rounded,
              tooltip: 'Center',
              onTap: () => _wrapSelection('~~~', '~~~', 'centered text'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mdBtn(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    final colors = context.colors;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(
            icon,
            size: 19,
            color: colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Floating trigger bar styled like the Home screen's FloatingPillNavBar.
/// Matches translucent / solid / OLED theme automatically and stays completely
/// lag-free because it does not host a live TextField on the thread page.
class AnilistThreadComposerTrigger extends StatelessWidget {
  final TextEditingController controller;
  final AnilistThreadComment? replyingTo;
  final VoidCallback onTap;
  final VoidCallback? onCancelReply;
  final bool isLocked;
  final bool hasAuthToken;

  const AnilistThreadComposerTrigger({
    super.key,
    required this.controller,
    required this.replyingTo,
    required this.onTap,
    this.onCancelReply,
    required this.isLocked,
    required this.hasAuthToken,
  });

  String? get _userAvatarUrl {
    if (!Get.isRegistered<AnilistAuth>()) return null;
    final url = Get.find<AnilistAuth>().profileData.value.avatar;
    if (url == null || url.trim().isEmpty) return null;
    return url.trim();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isOled = _isAppOledDark(context);
    final isDesktop = MediaQuery.sizeOf(context).width > 600;
    final bottomPadding =
        isDesktop ? 0.0 : MediaQuery.paddingOf(context).bottom;
    final barRadius = BorderRadius.circular(
      isDesktop ? 30.multiplyRadius() : 36.multiplyRadius(),
    );
    final barWidth = isDesktop
        ? 540.0
        : (MediaQuery.sizeOf(context).width * 0.88).clamp(260.0, 540.0);

    Widget buildShell(Widget inner) {
      return RepaintBoundary(
        child: Align(
          alignment: Alignment.bottomCenter,
          heightFactor: 1.0,
          child: SizedBox(
            width: barWidth,
            child: Container(
              margin: EdgeInsets.only(
                top: 8,
                bottom: (isDesktop ? 16 : settingsController.bottomNavBarMargin) +
                    bottomPadding,
              ),
              decoration: BoxDecoration(
                borderRadius: barRadius,
                border: Border.all(
                  color: colors.onSurface.opaque(0.12, iReallyMeanIt: true),
                  width: 0.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.opaque(0.18, iReallyMeanIt: true),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: barRadius,
                child: Obx(() {
                  final isTranslucent =
                      settingsController.transculentBar;
                  final bgColor = isOled
                      ? (isTranslucent
                          ? Colors.black.withValues(alpha: 0.65)
                          : Colors.black)
                      : (isTranslucent
                          ? colors.surfaceContainer.withValues(alpha: 0.35)
                          : colors.surfaceContainer.withValues(alpha: 0.95));

                  final box = Container(
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: barRadius,
                    ),
                    child: inner,
                  );

                  if (!isTranslucent) return box;
                  return BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: box,
                  );
                }),
              ),
            ),
          ),
        ),
      );
    }

    if (isLocked || !hasAuthToken) {
      return buildShell(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isLocked ? Icons.lock_outline_rounded : Icons.login_rounded,
                size: 16,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: AnymeXText(
                  isLocked
                      ? 'This thread is locked'
                      : 'Log in to AniList to comment',
                  size: 13,
                  color: colors.onSurfaceVariant,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final avatarUrl = _userAvatarUrl;

    return buildShell(
      Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: barRadius,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.onSurface.opaque(0.08, iReallyMeanIt: true),
                    border: Border.all(
                      color: colors.onSurface.opaque(0.14, iReallyMeanIt: true),
                    ),
                  ),
                  child: ClipOval(
                    child: avatarUrl != null
                        ? AnymeXImage(
                            imageUrl: avatarUrl,
                            width: 36,
                            height: 36,
                            radius: 18,
                            fit: BoxFit.cover,
                          )
                        : Icon(
                            Icons.person_rounded,
                            size: 18,
                            color: colors.onSurfaceVariant,
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, val, _) {
                      final draft = val.text.trim();
                      final hasDraft = draft.isNotEmpty;
                      final label = hasDraft
                          ? draft.replaceAll('\n', ' ')
                          : (replyingTo != null
                              ? 'Reply to @${replyingTo!.user?.name ?? 'comment'}...'
                              : 'Comment on thread...');
                      return AnymeXText(
                        label,
                        size: 14,
                        color: hasDraft
                            ? colors.onSurface
                            : colors.onSurfaceVariant
                                .opaque(0.75, iReallyMeanIt: true),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      );
                    },
                  ),
                ),
                if (replyingTo != null && onCancelReply != null)
                  InkWell(
                    onTap: onCancelReply,
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        Icons.close_rounded,
                        size: 17,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(
                      Icons.edit_outlined,
                      size: 17,
                      color: colors.primary,
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

/// Isolated modal bottom sheet composer. Running on its own ModalRoute keeps
/// typing and keyboard animations decoupled from the thread page's HtmlWidgets.
class AnilistThreadComposerSheet extends StatefulWidget {
  final TextEditingController controller;
  final ValueNotifier<AnilistThreadComment?> replyingToNotifier;
  final Future<bool> Function(String text, int? parentCommentId) onSubmit;

  const AnilistThreadComposerSheet({
    super.key,
    required this.controller,
    required this.replyingToNotifier,
    required this.onSubmit,
  });

  static Future<void> show(
    BuildContext context, {
    required TextEditingController controller,
    required ValueNotifier<AnilistThreadComment?> replyingToNotifier,
    required Future<bool> Function(String text, int? parentCommentId) onSubmit,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (_) => AnilistThreadComposerSheet(
        controller: controller,
        replyingToNotifier: replyingToNotifier,
        onSubmit: onSubmit,
      ),
    );
  }

  @override
  State<AnilistThreadComposerSheet> createState() =>
      _AnilistThreadComposerSheetState();
}

class _AnilistThreadComposerSheetState
    extends State<AnilistThreadComposerSheet> {
  final FocusNode _focusNode = FocusNode();
  bool _isPreview = false;
  bool _isSending = false;
  bool _hasContentState = false;
  bool _isMultilineState = false;
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _avatarUrl = _resolveAvatarUrl();
    _syncDerivedState();
    widget.controller.addListener(_onTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _focusNode.dispose();
    super.dispose();
  }

  String? _resolveAvatarUrl() {
    if (!Get.isRegistered<AnilistAuth>()) return null;
    final url = Get.find<AnilistAuth>().profileData.value.avatar;
    if (url == null || url.trim().isEmpty) return null;
    return url.trim();
  }

  void _syncDerivedState() {
    final raw = widget.controller.text;
    _hasContentState = raw.trim().isNotEmpty;
    _isMultilineState = _isPreview || raw.contains('\n') || raw.length > 36;
  }

  void _onTextChanged() {
    final raw = widget.controller.text;
    final nextHasContent = raw.trim().isNotEmpty;
    final nextPreview = nextHasContent ? _isPreview : false;
    final nextMultiline = nextPreview || raw.contains('\n') || raw.length > 36;

    if (nextHasContent == _hasContentState &&
        nextMultiline == _isMultilineState &&
        nextPreview == _isPreview) {
      return;
    }

    if (mounted) {
      setState(() {
        _hasContentState = nextHasContent;
        _isMultilineState = nextMultiline;
        _isPreview = nextPreview;
      });
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

  void _setPreviewMode(bool preview) {
    setState(() {
      _isPreview = preview;
      _syncDerivedState();
    });
    if (preview) {
      _focusNode.unfocus();
    } else {
      _focusNode.requestFocus();
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
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isOled = _isAppOledDark(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final cardBg = isOled ? Colors.black : colors.surfaceContainer;
    final pillBg = isOled
        ? const Color(0xFF141418)
        : colors.surfaceContainerHighest.opaque(0.75, iReallyMeanIt: true);
    final borderCol = colors.onSurface.opaque(0.12, iReallyMeanIt: true);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        10,
        0,
        10,
        bottomInset > 0 ? bottomInset + 8 : 12,
      ),
      child: Center(
        heightFactor: 1.0,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Material(
            color: cardBg,
            borderRadius: BorderRadius.circular(26),
            elevation: isOled ? 0 : 6,
            shadowColor: Colors.black.withValues(alpha: 0.4),
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: borderCol, width: 0.8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Replying-to quote banner
                  ValueListenableBuilder<AnilistThreadComment?>(
                    valueListenable: widget.replyingToNotifier,
                    builder: (context, replyingTo, _) {
                      if (replyingTo == null) return const SizedBox.shrink();
                      final snippet = _plainSnippet(replyingTo.commentHtml);
                      return Container(
                        margin: const EdgeInsets.fromLTRB(2, 0, 2, 8),
                        padding: const EdgeInsets.fromLTRB(10, 7, 8, 7),
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.11),
                          borderRadius: BorderRadius.circular(14),
                          border: Border(
                            left: BorderSide(color: colors.primary, width: 3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.subdirectory_arrow_right_rounded,
                              size: 16,
                              color: colors.primary,
                            ),
                            const SizedBox(width: 7),
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
                              onTap: () =>
                                  widget.replyingToNotifier.value = null,
                              borderRadius: BorderRadius.circular(12),
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
                      );
                    },
                  ),

                  // Row 1: Avatar + Input/Preview Pill + External Preview/Send buttons
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: _buildUserAvatar(colors, pillBg),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          constraints: const BoxConstraints(
                            minHeight: 44,
                            maxHeight: 160,
                          ),
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 11,
                          ),
                          decoration: BoxDecoration(
                            color: pillBg,
                            borderRadius: BorderRadius.circular(
                              _isMultilineState ? 22 : 28,
                            ),
                          ),
                          child: _isPreview
                              ? SingleChildScrollView(
                                  child: _hasContentState
                                      ? AnilistAboutMe(
                                          about: parseMarkdown(
                                            widget.controller.text,
                                          ),
                                        )
                                      : AnymeXText(
                                          'Nothing to preview',
                                          size: 14,
                                          fontStyle: FontStyle.italic,
                                          color: colors.onSurfaceVariant,
                                        ),
                                )
                              : ValueListenableBuilder<AnilistThreadComment?>(
                                  valueListenable: widget.replyingToNotifier,
                                  builder: (context, replyingTo, _) {
                                    return TextField(
                                      controller: widget.controller,
                                      focusNode: _focusNode,
                                      minLines: 1,
                                      maxLines: 6,
                                      keyboardType: TextInputType.multiline,
                                      textInputAction: TextInputAction.newline,
                                      textAlignVertical:
                                          TextAlignVertical.center,
                                      style: TextStyle(
                                        color: colors.onSurface,
                                        fontSize: 14.5,
                                        height: 1.35,
                                      ),
                                      decoration: InputDecoration(
                                        filled: false,
                                        fillColor: Colors.transparent,
                                        isCollapsed: true,
                                        contentPadding: EdgeInsets.zero,
                                        hintText: replyingTo != null
                                            ? 'Reply to @${replyingTo.user?.name ?? 'comment'}...'
                                            : 'Comment on thread...',
                                        hintStyle: TextStyle(
                                          color: colors.onSurfaceVariant
                                              .opaque(0.7, iReallyMeanIt: true),
                                          fontSize: 14.5,
                                        ),
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ),
                      if (_hasContentState)
                        Padding(
                          padding: const EdgeInsets.only(left: 8, bottom: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _circleButton(
                                tooltip: _isPreview ? 'Compose' : 'Preview',
                                background: pillBg,
                                foreground: _isPreview
                                    ? colors.primary
                                    : colors.onSurface,
                                icon: _isPreview
                                    ? Icons.edit_rounded
                                    : Icons.preview_rounded,
                                onTap: () => _setPreviewMode(!_isPreview),
                              ),
                              const SizedBox(width: 6),
                              _circleButton(
                                tooltip: 'Send',
                                background: colors.primary,
                                foreground: colors.onPrimary,
                                icon: Icons.send_rounded,
                                isLoading: _isSending,
                                onTap: _isSending ? null : _handleSend,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),

                  // Row 2: Scrollable Markdown Toolbar (hidden during Preview)
                  if (!_isPreview)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: AnilistMarkdownToolbar(
                        controller: widget.controller,
                        focusNode: _focusNode,
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

  Widget _buildUserAvatar(ColorScheme colors, Color fallbackBg) {
    final url = _avatarUrl;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fallbackBg,
        border: Border.all(
          color: colors.onSurface.opaque(0.14, iReallyMeanIt: true),
        ),
      ),
      child: ClipOval(
        child: url != null
            ? AnymeXImage(
                imageUrl: url,
                width: 40,
                height: 40,
                radius: 20,
                fit: BoxFit.cover,
              )
            : Icon(
                Icons.person_rounded,
                size: 20,
                color: colors.onSurfaceVariant,
              ),
      ),
    );
  }

  Widget _circleButton({
    required String tooltip,
    required Color background,
    required Color foreground,
    required IconData icon,
    VoidCallback? onTap,
    bool isLoading = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: background,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: isLoading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation<Color>(foreground),
                      ),
                    )
                  : Icon(icon, size: 19, color: foreground),
            ),
          ),
        ),
      ),
    );
  }
}
