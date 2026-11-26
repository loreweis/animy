import 'package:anymex/controllers/services/anilist/anilist_auth.dart';
import 'package:anymex/models/Anilist/anilist_thread.dart';
import 'package:anymex/screens/anime/widgets/comments/widgets/gif_picker_sheet.dart';
import 'package:anymex/utils/al_about_me.dart';
import 'package:anymex/utils/markdown.dart';
import 'package:anymex/utils/theme_extensions.dart';
import 'package:anymex/widgets/anymex_widgets/anymex_image.dart';
import 'package:anymex/widgets/anymex_widgets/anymex_text.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AnilistThreadComposer extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final AnilistThreadComment? replyingTo;
  final VoidCallback onCancelReply;
  final Future<void> Function() onSend;
  final bool isSending;
  final bool isLocked;
  final bool hasAuthToken;

  const AnilistThreadComposer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.replyingTo,
    required this.onCancelReply,
    required this.onSend,
    required this.isSending,
    required this.isLocked,
    required this.hasAuthToken,
  });

  @override
  State<AnilistThreadComposer> createState() => _AnilistThreadComposerState();
}

class _AnilistThreadComposerState extends State<AnilistThreadComposer> {
  bool _isPreview = false;
  bool _hasContentState = false;
  bool _isMultilineState = false;

  @override
  void initState() {
    super.initState();
    _syncDerivedState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(covariant AnilistThreadComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      _syncDerivedState();
      widget.controller.addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
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

  bool get _hasContent => _hasContentState;

  bool get _isMultiline => _isMultilineState;

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

  String? get _userAvatarUrl {
    if (!Get.isRegistered<AnilistAuth>()) return null;
    final url = Get.find<AnilistAuth>().profileData.value.avatar;
    if (url == null || url.trim().isEmpty) return null;
    return url.trim();
  }

  void _setPreviewMode(bool preview) {
    setState(() {
      _isPreview = preview;
      _syncDerivedState();
    });
    if (preview) {
      widget.focusNode.unfocus();
    } else {
      widget.focusNode.requestFocus();
    }
  }

  void _wrapSelection(String before, String after, String placeholder) {
    if (_isPreview) {
      _setPreviewMode(false);
    }
    final text = widget.controller.text;
    final sel = widget.controller.selection;
    final hasValidSel = sel.start >= 0 && sel.end >= sel.start;
    final start = hasValidSel ? sel.start : text.length;
    final end = hasValidSel ? sel.end : text.length;

    final selected = start < end ? text.substring(start, end) : placeholder;
    final replacement = '$before$selected$after';
    final updated = text.replaceRange(start, end, replacement);

    widget.controller.value = TextEditingValue(
      text: updated,
      selection: TextSelection(
        baseOffset: start + before.length,
        extentOffset: start + before.length + selected.length,
      ),
    );
    widget.focusNode.requestFocus();
  }

  String _detectUrlKind(String raw) {
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

  Future<void> _insertSmartUrl() async {
    final urlCtrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final colors = ctx.colors;
            final current = urlCtrl.text.trim();
            final kind = _detectUrlKind(current);
            final (label, icon) = switch (kind) {
              'youtube' => ('YouTube · youtube(...)', Icons.smart_display_rounded),
              'webm' => ('Video · webm(...)', Icons.videocam_rounded),
              'image' => ('Image · img(...)', Icons.image_outlined),
              _ => ('Link · [text](...)', Icons.link_rounded),
            };

            return AlertDialog(
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
                      fillColor: colors.surfaceContainerHighest
                          .opaque(0.4, iReallyMeanIt: true),
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
                          ? colors.surfaceContainerHighest
                              .opaque(0.35, iReallyMeanIt: true)
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
                        AnymeXText(
                          current.isEmpty
                              ? 'Auto-detects Link, Image, YouTube & WebM'
                              : 'Detected: $label',
                          size: 11.5,
                          variant: TextVariant.semiBold,
                          color: current.isEmpty
                              ? colors.onSurfaceVariant
                              : colors.primary,
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

    if (!mounted || result == null || result.isEmpty) return;

    final normalized =
        result.contains('://') ? result : 'https://$result';
    switch (_detectUrlKind(normalized)) {
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

  void _insertLinePrefix(String prefix, String placeholder) {
    if (_isPreview) {
      _setPreviewMode(false);
    }
    final text = widget.controller.text;
    final sel = widget.controller.selection;
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
      widget.controller.value = TextEditingValue(
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
      widget.controller.value = TextEditingValue(
        text: updated,
        selection: TextSelection(
          baseOffset: start + lead.length,
          extentOffset: start + lead.length + placeholder.length,
        ),
      );
    }
    widget.focusNode.requestFocus();
  }

  void _openGifPicker() {
    if (_isPreview) {
      _setPreviewMode(false);
    }
    GifPickerSheet.show(
      context,
      onGifSelected: (gifUrl) {
        final clean = gifUrl.trim();
        if (clean.isEmpty) return;
        _insertRaw('img($clean)');
      },
    );
  }

  void _insertRaw(String snippet) {
    final text = widget.controller.text;
    final sel = widget.controller.selection;
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
    widget.controller.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: start + insertion.length),
    );
    widget.focusNode.requestFocus();
  }

  Future<void> _handleSend() async {
    if (!_hasContent || widget.isSending) return;
    await widget.onSend();
    if (mounted && !widget.controller.text.trim().isNotEmpty && _isPreview) {
      setState(() => _isPreview = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (widget.isLocked || !widget.hasAuthToken) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                decoration: BoxDecoration(
                  color: colors.surfaceContainer.opaque(0.95, iReallyMeanIt: true),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: colors.outlineVariant.opaque(0.28, iReallyMeanIt: true),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.28),
                      blurRadius: 8,
                      offset: const Offset(0, 6),
                    ),
                  ],
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
                            : 'Log in to AniList to post replies or like comments',
                        size: 12.5,
                        color: colors.onSurfaceVariant,
                        textAlign: TextAlign.center,
                        maxLines: 2,
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
      child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
              decoration: BoxDecoration(
                color: colors.surfaceContainer.opaque(0.96, iReallyMeanIt: true),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: colors.outlineVariant.opaque(0.28, iReallyMeanIt: true),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.32),
                    blurRadius: 8,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Replying-to quote banner (clearly distinguishes reply-to-comment vs reply-to-thread)
                  AnimatedSize(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    child: widget.replyingTo == null
                        ? const SizedBox.shrink()
                        : Container(
                            margin: const EdgeInsets.fromLTRB(2, 0, 2, 8),
                            padding: const EdgeInsets.fromLTRB(10, 7, 8, 7),
                            decoration: BoxDecoration(
                              color: colors.primary.withValues(alpha: 0.11),
                              borderRadius: BorderRadius.circular(14),
                              border: Border(
                                left: BorderSide(
                                  color: colors.primary,
                                  width: 3,
                                ),
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      AnymeXText(
                                        'Replying to @${widget.replyingTo!.user?.name ?? 'comment'}',
                                        size: 11.5,
                                        variant: TextVariant.bold,
                                        color: colors.primary,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (_plainSnippet(widget
                                              .replyingTo!.commentHtml)
                                          .isNotEmpty)
                                        AnymeXText(
                                          _plainSnippet(widget
                                              .replyingTo!.commentHtml),
                                          size: 11,
                                          color: colors.onSurfaceVariant,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                ),
                                InkWell(
                                  onTap: widget.onCancelReply,
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
                          ),
                  ),

                  // Row 1: Avatar + Input/Preview Pill + External Preview & Send Buttons
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: _buildUserAvatar(colors),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          curve: Curves.easeOutCubic,
                          constraints: const BoxConstraints(
                            minHeight: 44,
                            maxHeight: 160,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerHighest
                                .opaque(0.75, iReallyMeanIt: true),
                            borderRadius: BorderRadius.circular(
                              _isMultiline ? 22 : 28,
                            ),
                          ),
                          child: _isPreview
                              ? SingleChildScrollView(
                                  child: _hasContent
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
                              : TextField(
                                  controller: widget.controller,
                                  focusNode: widget.focusNode,
                                  minLines: 1,
                                  maxLines: 6,
                                  keyboardType: TextInputType.multiline,
                                  textInputAction: TextInputAction.newline,
                                  style: TextStyle(
                                    color: colors.onSurface,
                                    fontSize: 14.5,
                                    height: 1.4,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: widget.replyingTo != null
                                        ? 'Reply to @${widget.replyingTo!.user?.name ?? 'comment'}...'
                                        : 'Comment on thread...',
                                    hintStyle: TextStyle(
                                      color: colors.onSurfaceVariant
                                          .opaque(0.7, iReallyMeanIt: true),
                                      fontSize: 14.5,
                                    ),
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                  ),
                                ),
                        ),
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        child: _hasContent
                            ? Padding(
                                padding:
                                    const EdgeInsets.only(left: 8, bottom: 2),
                                child: AnimatedScale(
                                  duration: const Duration(milliseconds: 200),
                                  scale: _hasContent ? 1.0 : 0.85,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _circleButton(
                                        tooltip: _isPreview
                                            ? 'Compose'
                                            : 'Preview',
                                        background: colors
                                            .surfaceContainerHighest
                                            .opaque(0.9, iReallyMeanIt: true),
                                        foreground: _isPreview
                                            ? colors.primary
                                            : colors.onSurface,
                                        icon: _isPreview
                                            ? Icons.edit_rounded
                                            : Icons.preview_rounded,
                                        onTap: () =>
                                            _setPreviewMode(!_isPreview),
                                      ),
                                      const SizedBox(width: 6),
                                      _circleButton(
                                        tooltip: 'Send',
                                        background: colors.primary,
                                        foreground: colors.onPrimary,
                                        icon: Icons.send_rounded,
                                        isLoading: widget.isSending,
                                        onTap: widget.isSending
                                            ? null
                                            : _handleSend,
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),

                  // Row 2: Markdown Toolbar (collapses smoothly during Preview)
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: _isPreview
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: SizedBox(
                              height: 36,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                physics: const BouncingScrollPhysics(),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 2),
                                child: Row(
                                  children: [
                                    _mdBtn(
                                      icon: Icons.format_bold_rounded,
                                      tooltip: 'Bold',
                                      onTap: () => _wrapSelection(
                                          '**', '**', 'bold text'),
                                    ),
                                    _mdBtn(
                                      icon: Icons.format_italic_rounded,
                                      tooltip: 'Italic',
                                      onTap: () => _wrapSelection(
                                          '*', '*', 'italic text'),
                                    ),
                                    _mdBtn(
                                      icon: Icons.format_strikethrough_rounded,
                                      tooltip: 'Strikethrough',
                                      onTap: () => _wrapSelection(
                                          '~~', '~~', 'strikethrough'),
                                    ),
                                    _mdBtn(
                                      icon: Icons.visibility_off_rounded,
                                      tooltip: 'Spoiler',
                                      onTap: () => _wrapSelection(
                                          '~!', '!~', 'spoiler'),
                                    ),
                                    _mdBtn(
                                      icon: Icons.code_rounded,
                                      tooltip: 'Inline Code',
                                      onTap: () =>
                                          _wrapSelection('`', '`', 'code'),
                                    ),
                                    _mdBtn(
                                      icon:
                                          Icons.integration_instructions_rounded,
                                      tooltip: 'Code Block',
                                      onTap: () => _wrapSelection(
                                          '```\n', '\n```', 'code block'),
                                    ),
                                    _mdBtn(
                                      icon: Icons.add_link_rounded,
                                      tooltip:
                                          'Insert URL (Link / Image / YouTube / WebM)',
                                      onTap: _insertSmartUrl,
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 4),
                                      child: _gifPillButton(colors),
                                    ),
                                    _mdBtn(
                                      icon: Icons.format_quote_rounded,
                                      tooltip: 'Quote',
                                      onTap: () =>
                                          _insertLinePrefix('> ', 'quote'),
                                    ),
                                    _mdBtn(
                                      icon: Icons.format_list_bulleted_rounded,
                                      tooltip: 'Bullet List',
                                      onTap: () =>
                                          _insertLinePrefix('- ', 'list item'),
                                    ),
                                    _mdBtn(
                                      icon: Icons.format_list_numbered_rounded,
                                      tooltip: 'Numbered List',
                                      onTap: () =>
                                          _insertLinePrefix('1. ', 'list item'),
                                    ),
                                    _mdBtn(
                                      icon: Icons.title_rounded,
                                      tooltip: 'Header',
                                      onTap: () =>
                                          _insertLinePrefix('# ', 'heading'),
                                    ),
                                    _mdBtn(
                                      icon: Icons.format_align_center_rounded,
                                      tooltip: 'Center',
                                      onTap: () => _wrapSelection(
                                          '~~~', '~~~', 'centered text'),
                                    ),

                                  ],
                                ),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildUserAvatar(ColorScheme colors) {
    final avatarUrl = _userAvatarUrl;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.surfaceContainerHighest.opaque(0.7, iReallyMeanIt: true),
        border: Border.all(
          color: colors.outlineVariant.opaque(0.35, iReallyMeanIt: true),
        ),
      ),
      child: ClipOval(
        child: avatarUrl != null
            ? AnymeXImage(
                imageUrl: avatarUrl,
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

  Widget _mdBtn({
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

  Widget _gifPillButton(ColorScheme colors) {
    return Tooltip(
      message: 'Insert GIF',
      child: Material(
        color: colors.primary.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          onTap: _openGifPicker,
          borderRadius: BorderRadius.circular(15),
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 11),
            alignment: Alignment.center,
            child: AnymeXText(
              'GIF',
              size: 11,
              variant: TextVariant.bold,
              color: colors.primary,
            ),
          ),
        ),
      ),
    );
  }
}
