import 'package:anymex/l10n/l10n_extension.dart';
import 'dart:math' as math;

import 'package:anymex/controllers/offline/offline_storage_controller.dart';
import 'package:anymex/controllers/service_handler/service_handler.dart';
import 'package:anymex/controllers/settings/settings.dart';
import 'package:anymex/controllers/source/source_controller.dart';
import 'package:anymex/database/data_keys/keys.dart';
import 'package:anymex/utils/theme_extensions.dart';
import 'package:anymex/widgets/common/reusable_carousel.dart';
import 'package:anymex/widgets/common/scroll_aware_app_bar.dart';
import 'package:anymex/widgets/dialogs/donation_dialog.dart';
import 'package:anymex/widgets/anymex_widgets/anymex_text.dart';
import 'package:anymex/widgets/anymex_widgets/anymex_textspan.dart';
import 'package:anymex/widgets/header/header.dart';
import 'package:anymex/widgets/helper/platform_builder.dart';
import 'package:anymex/widgets/history/tap_history_cards.dart';
import 'package:anymex/widgets/non_widgets/snackbar.dart';
import 'package:anymex/models/Media/media.dart';
import 'package:anymex/widgets/media_items/media_item.dart';
import 'package:anymex_extension_runtime_bridge/anymex_extension_runtime_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:shimmer/shimmer.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late ScrollController _scrollController;
  final ValueNotifier<bool> _isAppBarVisibleExternally =
      ValueNotifier<bool>(true);
  final List<Worker> _workers = [];

  Widget _buildNewEpisodesSection() {
    final serviceHandler = Get.find<ServiceHandler>();
    return Obx(() {
      final entries = <(Media, int, int, DateTime?)>[];

      if (serviceHandler.isLoggedIn.value ||
          serviceHandler.animeList.isNotEmpty) {
        final now = DateTime.now();
        for (final item in serviceHandler.animeList) {
          if (item.type?.toUpperCase() == 'MANGA' || item.id == null) continue;
          final watched = item.effectiveProgress;
          int latestReleased = 0;
          if (item.releasedEpisodes != null &&
              item.releasedEpisodes!.isNotEmpty) {
            latestReleased = int.tryParse(item.releasedEpisodes!) ?? 0;
          } else if (item.mediaStatus?.toUpperCase() == 'COMPLETED' ||
              item.mediaStatus?.toUpperCase() == 'FINISHED') {
            latestReleased = int.tryParse(item.totalEpisodes ?? '') ?? 0;
          }

          final status = item.watchingStatus?.toUpperCase();
          final isWatching = status == 'CURRENT' ||
              status == 'WATCHING' ||
              status == 'REPEATING' ||
              status == 'REWATCHING';

          if (!isWatching || latestReleased <= watched) {
            continue;
          }

          final media = CardData.fromTrackedMedia(item).data;
          final releaseDate = NewEpisodeReleaseCard.calculateReleaseDate(
            media: media,
            latestReleasedEpisode: latestReleased,
            itemEndDate: item.endDate,
            mediaStatus: item.mediaStatus,
          );

          final mediaStatus = item.mediaStatus?.toUpperCase();
          final isStillAiring = mediaStatus == 'RELEASING' ||
              mediaStatus == 'AIRING' ||
              item.nextAiringEpisode != null;

          if (!isStillAiring) {
            if (releaseDate == null ||
                now.isAfter(releaseDate.add(const Duration(days: 7)))) {
              continue;
            }
          }

          entries.add((media, watched, latestReleased, releaseDate));
        }

        entries.sort((a, b) {
          final dateA = a.$4;
          final dateB = b.$4;
          if (dateA == null && dateB == null) return 0;
          if (dateA == null) return 1;
          if (dateB == null) return -1;
          return dateB.compareTo(dateA);
        });
      }

      if (entries.isEmpty) {
        return const SizedBox.shrink();
      }

      final isDesktop = MediaQuery.sizeOf(context).width > 600;
      final horizontalPadding = isDesktop ? 24.0 : 20.0;

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 110,
              child: RepaintBoundary(
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(right: 15),
                  itemCount: entries.length,
                  itemBuilder: (context, i) => NewEpisodeReleaseCard(
                    media: entries[i].$1,
                    watchedEpisode: entries[i].$2,
                    latestReleasedEpisode: entries[i].$3,
                    releaseDate: entries[i].$4,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  int _estimateSkeletonCarouselCount(
    ServiceHandler serviceHandler,
    Settings settings,
    bool expectLoggedIn,
  ) {
    switch (serviceHandler.serviceType.value) {
      case ServicesType.anilist:
        final cards = settings.homePageCards;
        if (expectLoggedIn) {
          final enabled = cards.values.where((v) => v).length;
          return enabled.clamp(2, 6);
        }
        final recCount = (cards['Recommended Animes'] == true ? 1 : 0) +
            (cards['Recommended Mangas'] == true ? 1 : 0);
        return recCount.clamp(1, 2);
      case ServicesType.mal:
        final accountCount = expectLoggedIn
            ? settings.homePageCardsMal.values.where((v) => v).length
            : 0;
        return (accountCount + 4).clamp(2, 6);
      case ServicesType.simkl:
        final accountCount = expectLoggedIn
            ? settings.homePageCardsSimkl.values.where((v) => v).length
            : 0;
        return (accountCount + 2).clamp(2, 5);
      case ServicesType.extensions:
        return 2;
    }
  }

  Widget _buildHomeSkeleton({
    required BuildContext context,
    required Settings settings,
    required bool showQuickButtons,
    required int carouselCount,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isDesktop = MediaQuery.sizeOf(context).width > 600;
    final baseColor =
        theme.colorScheme.onSurface.withValues(alpha: isDark ? 0.08 : 0.09);
    final highlightColor =
        theme.colorScheme.onSurface.withValues(alpha: isDark ? 0.16 : 0.18);
    final config = settings.customCardStyle;
    final isLandscape = config.isLandscape;
    final cardWidth = isLandscape
        ? (isDesktop ? 230.0 : 185.0)
        : (isDesktop ? 150.0 : 112.0);
    final cardHeight = isLandscape
        ? (cardWidth / config.ratioValue).clamp(96.0, 145.0)
        : (cardWidth / config.ratioValue).clamp(145.0, 210.0);
    final buttonHeight = isDesktop ? 90.0 : 70.0;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showQuickButtons)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: buttonHeight,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Container(
                          height: buttonHeight,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    height: buttonHeight,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
              ),
            ),
          ...List.generate(
            carouselCount,
            (_) => Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 20, bottom: 12),
                    child: Container(
                      width: 150,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: cardHeight + 34,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(left: 16),
                      itemCount: isLandscape ? 3 : 4,
                      itemBuilder: (_, __) => Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: SizedBox(
                          width: cardWidth,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: cardWidth,
                                height: cardHeight,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                width: cardWidth * 0.8,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(5),
                                ),
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
        ],
      ),
    );
  }

  List<Widget> _buildHomeWidgets({
    required BuildContext context,
    required ServiceHandler serviceHandler,
    required OfflineStorageController offlineStorageController,
    required Settings settings,
  }) {
    final baseWidgets = serviceHandler.homeWidgets(context);
    final localSections = <Widget>[
      _buildNewEpisodesSection(),
    ];

    int insertionIndex;
    if (serviceHandler.serviceType.value == ServicesType.simkl) {
      insertionIndex = serviceHandler.isLoggedIn.value ? 3 : 2;
    } else if (!serviceHandler.isLoggedIn.value ||
        serviceHandler.serviceType.value == ServicesType.extensions) {
      insertionIndex = 0;
    } else {
      insertionIndex = 2;
    }
    insertionIndex = math.min(insertionIndex, baseWidgets.length);

    return [
      ...baseWidgets.take(insertionIndex),
      ...localSections,
      ...baseWidgets.skip(insertionIndex),
    ];
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    final serviceHandler = Get.find<ServiceHandler>();
    _workers.add(ever(serviceHandler.serviceType, (_) {
      if (mounted) setState(() {});
    }));
    _workers.add(ever(serviceHandler.anilistService.isLoggedIn, (_) {
      if (mounted) setState(() {});
    }));
    _workers.add(ever(serviceHandler.malService.isLoggedIn, (_) {
      if (mounted) setState(() {});
    }));
    _workers.add(ever(serviceHandler.simklService.isLoggedIn, (_) {
      if (mounted) setState(() {});
    }));
    _workers.add(ever(serviceHandler.isHomeLoading, (_) {
      if (mounted) setState(() {});
    }));
    _workers.add(ever(serviceHandler.isAutoLoggingIn, (_) {
      if (mounted) setState(() {});
    }));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndShowDonationDialog();
    });
  }

  void _checkAndShowDonationDialog() {
    if (!mounted) return;
    final hasShown = General.hasShownHomeDonationDialog.get<bool>(false);
    if (hasShown) return;

    if (General.isFirstTime.get<bool>(true)) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _checkAndShowDonationDialog();
      });
      return;
    }

    General.hasShownHomeDonationDialog.set(true);
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) {
        DonationDialog.show(context);
      }
    });
  }

  ScrollController get scrollController => _scrollController;

  @override
  void dispose() {
    for (final w in _workers) {
      w.dispose();
    }
    _workers.clear();
    _scrollController.dispose();
    _isAppBarVisibleExternally.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final offlineStorageController = Get.find<OfflineStorageController>();
    final serviceHandler = Get.find<ServiceHandler>();
    final settings = Get.find<Settings>();
    final sourceController = Get.find<SourceController>();
    final isDesktop = MediaQuery.sizeOf(context).width > 600;
    final statusBarHeight = MediaQuery.paddingOf(context).top;
    const appBarHeight = kToolbarHeight + 20;
    final double bottomNavBarHeight =
        isDesktop ? 20.0 : (MediaQuery.paddingOf(context).bottom + 65.0);
    final bool isMobile =
        getResponsiveValue(context, desktopValue: false, mobileValue: true);
    final TextAlign textAlignment =
        isMobile ? TextAlign.center : TextAlign.left;
    final bool expectLoggedIn = serviceHandler.isLoggedIn.value ||
        (serviceHandler.isAutoLoggingIn.value &&
            serviceHandler.hasSavedTokenForActiveService);
    final bool showLegacyHero =
        serviceHandler.serviceType.value != ServicesType.anilist ||
            !expectLoggedIn;
    final bool waitingForAccountLists = serviceHandler.isAutoLoggingIn.value &&
        serviceHandler.hasSavedTokenForActiveService;
    final bool showHomeSkeleton =
        serviceHandler.isHomeLoading.value || waitingForAccountLists;

    final List<dynamic> novelData = [];

    return RefreshIndicator(
      onRefresh: () {
        if (!serviceHandler.isLoggedIn.value) {
          snackBar(context.l10n.wWhatAreYouDoingStep, duration: 1200);
        }
        return serviceHandler.refresh();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        extendBodyBehindAppBar: true,
        body: Stack(
          children: [
            PrimaryScrollController(
              controller: _scrollController,
              child: CustomScrollView(
                controller: _scrollController,
                cacheExtent: 200.0,
                slivers: [
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: statusBarHeight + appBarHeight + 10,
                    ),
                  ),
                  if (showLegacyHero) ...[
                    SliverToBoxAdapter(
                      child: Obx(
                        () => Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: isDesktop ? 24.0 : 20.0,
                          ),
                          child: AnymeXTextSpans(
                            fontSize: 27,
                            spans: [
                              AnymeXTextSpan(
                                  text: context.l10n.hey,
                                  size: 30,
                                  variant: TextVariant.bold),
                              AnymeXTextSpan(
                                  text: (serviceHandler.isLoggedIn.value &&
                                          (serviceHandler
                                                  .profileData.value.name?.isNotEmpty ??
                                              false))
                                      ? serviceHandler.profileData.value.name!
                                      : context.l10n.guest,
                                  size: 30,
                                  color: context.colors.primary,
                                  variant: TextVariant.bold),
                              AnymeXTextSpan(
                                  text: context.l10n.whatAreWeDoingToday,
                                  size: 30,
                                  variant: TextVariant.bold),
                            ],
                            textAlign: textAlignment,
                          ),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: isMobile
                            ? CrossAxisAlignment.center
                            : CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 10),
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: isDesktop ? 24.0 : 20.0,
                            ),
                            child: AnymeXText(
                              context.l10n.findYourFavouriteAnimeOrManga,
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .inverseSurface
                                    .withOpacity(0.8),
                              ),
                              textAlign: textAlignment,
                            ),
                          ),
                          const SizedBox(height: 30),
                        ],
                      ),
                    ),
                  ],
                  () {
                    if (showHomeSkeleton) {
                      return SliverToBoxAdapter(
                        child: _buildHomeSkeleton(
                          context: context,
                          settings: settings,
                          showQuickButtons: expectLoggedIn,
                          carouselCount: _estimateSkeletonCarouselCount(
                            serviceHandler,
                            settings,
                            expectLoggedIn,
                          ),
                        ),
                      );
                    }
                    final homeWidgets = _buildHomeWidgets(
                      context: context,
                      serviceHandler: serviceHandler,
                      offlineStorageController: offlineStorageController,
                      settings: settings,
                    );
                    return SliverList.builder(
                      itemCount: homeWidgets.length,
                      itemBuilder: (context, index) => RepaintBoundary(
                        child: homeWidgets[index],
                      ),
                    );
                  }(),
                  if (novelData.isNotEmpty)
                    SliverToBoxAdapter(
                      child: ReusableCarousel(
                        title: context.l10n.recommendedNovels,
                        data: novelData,
                        type: ItemType.novel,
                        source: sourceController.activeNovelSource.value,
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: SizedBox(height: bottomNavBarHeight + 150),
                  ),
                ],
              ),
            ),
            CustomAnimatedAppBar(
              isVisible: _isAppBarVisibleExternally,
              scrollController: _scrollController,
              headerContent: Header.fromType(type: PageType.home),
              visibleStatusBarStyle: SystemUiOverlayStyle(
                statusBarIconBrightness:
                    Theme.of(context).brightness == Brightness.light
                        ? Brightness.dark
                        : Brightness.light,
                statusBarBrightness: Theme.of(context).brightness,
                statusBarColor: Colors.transparent,
              ),
              hiddenStatusBarStyle: SystemUiOverlayStyle(
                statusBarIconBrightness:
                    Theme.of(context).brightness == Brightness.light
                        ? Brightness.light
                        : Brightness.dark,
                statusBarBrightness:
                    Theme.of(context).brightness == Brightness.light
                        ? Brightness.dark
                        : Brightness.light,
                statusBarColor: Colors.transparent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
