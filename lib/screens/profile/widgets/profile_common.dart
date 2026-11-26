import 'package:anymex/l10n/l10n_extension.dart';
import 'package:flutter/material.dart';
import 'package:anymex/widgets/helper/platform_builder.dart';
import 'package:anymex/widgets/non_widgets/activity_composer_sheet.dart';
import 'package:get/get.dart';
import 'package:anymex/controllers/settings/settings.dart';
import 'package:anymex/database/data_keys/keys.dart';
import 'package:anymex/widgets/anymex_widgets/anymex_image.dart';
import 'package:anymex/widgets/anymex_widgets/anymex_text.dart';

String getFollowLabel({bool? isFollowing, bool? isFollower}) {
  if (isFollowing == true && isFollower == true) return 'Mutual';
  if (isFollowing == true) return 'Following';
  if (isFollower == true) return 'Follows you';
  return 'Follow';
}

Future<bool> confirmDiscardComposer(
  BuildContext context, {
  required GlobalKey<ActivityComposerSheetState> composerKey,
  required String discardTitle,
  required String discardMessage,
}) async {
  final hasUnsavedText =
      (composerKey.currentState?.text.trim().isNotEmpty ?? false);
  if (!hasUnsavedText) return true;

  final discard = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: AnymeXText(discardTitle),
          content: AnymeXText(discardMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: AnymeXText(context.l10n.keepEditing),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: AnymeXText(context.l10n.discard),
            ),
          ],
        ),
      ) ??
      false;

  return discard;
}

Widget buildProfileSheetOption(
  BuildContext context, {
  required IconData icon,
  required String label,
  required VoidCallback onTap,
}) {
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Row(
        children: [
          Icon(icon,
              size: 20, color: context.theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 14),
          AnymeXText(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: context.theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    ),
  );
}

class PlaceholderTab extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const PlaceholderTab({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 60),
      child: Center(
        child: Column(
          children: [
            Icon(
              icon,
              size: 48,
              color:
                  context.theme.colorScheme.onSurfaceVariant.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            AnymeXText(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: context.theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            AnymeXText(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color:
                    context.theme.colorScheme.onSurfaceVariant.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StatRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool compact;

  const StatRow({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(compact ? 7 : 8),
          decoration: BoxDecoration(
            color: context.theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(compact ? 7 : 8),
          ),
          child: Icon(
            icon,
            size: compact ? 15 : 16,
            color: context.theme.colorScheme.onSurfaceVariant,
          ),
        ),
        SizedBox(width: compact ? 12 : 15),
        Expanded(
          child: AnymeXText(
            label,
            style: TextStyle(
              fontSize: compact ? 12.5 : 14,
              color: context.theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        AnymeXText(
          value,
          style: TextStyle(
            fontSize: compact ? 14 : 15,
            fontWeight: FontWeight.bold,
            color: context.theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}

void showActivityFilterSheet(
  BuildContext context, {
  required List<String> activityFilters,
  required VoidCallback onApply,
}) {
  const availableFilters = {
    'ANIME_LIST': 'Anime progress',
    'MANGA_LIST': 'Manga progress',
    'TEXT': 'Status',
    'MESSAGE': 'Messages',
  };

  showModalBottomSheet(
    context: context,
    backgroundColor: context.theme.colorScheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnymeXText(
                    context.l10n.filterActivity,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: context.theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  CheckboxListTile(
                    title: AnymeXText(context.l10n.all),
                    value: activityFilters.length == 4,
                    activeColor: context.theme.colorScheme.primary,
                    checkboxShape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                    onChanged: (val) {
                      setModalState(() {
                        if (val == true) {
                          activityFilters
                            ..clear()
                            ..addAll(availableFilters.keys);
                        } else {
                          activityFilters.clear();
                        }
                      });
                    },
                  ),
                  ...availableFilters.entries.map((entry) {
                    final isSelected = activityFilters.contains(entry.key);
                    return CheckboxListTile(
                      title: AnymeXText(entry.value),
                      value: isSelected,
                      activeColor: context.theme.colorScheme.primary,
                      checkboxShape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      onChanged: (val) {
                        setModalState(() {
                          if (val == true) {
                            activityFilters.add(entry.key);
                          } else {
                            activityFilters.remove(entry.key);
                          }
                        });
                      },
                    );
                  }),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: context.theme.colorScheme.primary,
                        foregroundColor: context.theme.colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        onApply();
                      },
                      child: AnymeXText(
                        context.l10n.applyFilters,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

class ProfileDesktopTabs extends StatelessWidget {
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;

  const ProfileDesktopTabs({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isDesktop = getResponsiveValue(
      context,
      mobileValue: false,
      desktopValue: true,
    );
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 40.0 : 20.0),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: context.theme.colorScheme.outlineVariant.withOpacity(0.3),
            ),
          ),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: labels.asMap().entries.map((entry) {
              final isSelected = selectedIndex == entry.key;
              return InkWell(
                onTap: () => onTabSelected(entry.key),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: isSelected
                            ? context.theme.colorScheme.primary
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: AnymeXText(
                    entry.value,
                    style: TextStyle(
                      fontFamily: 'Linotte',
                      fontSize: 14,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w600,
                      color: isSelected
                          ? context.theme.colorScheme.primary
                          : context.theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}


class ProfileBodyOnlyBanner extends StatelessWidget {
  final String imageUrl;
  final String? fallbackUrl;

  const ProfileBodyOnlyBanner({
    super.key,
    required this.imageUrl,
    this.fallbackUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isOled = settingsController.detailsOledMode;
      final _ = settingsController.detailsBlurScope;
      if (imageUrl.isEmpty) {
        return const SizedBox.shrink();
      }
      final brightness =
          UISettingsKeys.detailsBackdropBrightness.get<double>(1.0);
      final surface =
          isOled ? Colors.black : Theme.of(context).colorScheme.surface;

      return IgnorePointer(
        child: RepaintBoundary(
          child: Stack(
            fit: StackFit.expand,
            children: [
              ShaderMask(
                shaderCallback: (bounds) {
                  return const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.0, 0.72, 1.0],
                    colors: [
                      Colors.black,
                      Colors.black,
                      Colors.transparent,
                    ],
                  ).createShader(bounds);
                },
                blendMode: BlendMode.dstIn,
                child: ColorFiltered(
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
                  child: AnymeXImage(
                    imageUrl: imageUrl,
                    errorImage: fallbackUrl,
                    radius: 0,
                    width: double.infinity,
                    height: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.38, 0.78, 1.0],
                    colors: [
                      Colors.black.withValues(alpha: 0.35),
                      Colors.transparent,
                      surface.withValues(alpha: 0.45),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}
