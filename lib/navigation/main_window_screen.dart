import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/navigation/startup_work_gate.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/empty_library/empty_library_screen.dart';
import 'package:otzaria/empty_library/bloc/empty_library_bloc.dart';
import 'package:otzaria/find_ref/find_ref_dialog.dart';
import 'package:otzaria/search/view/search_dialog.dart';
import 'package:otzaria/library/view/library_browser.dart';
import 'package:otzaria/tabs/reading_screen.dart';
import 'package:otzaria/tools/more_screen.dart';
import 'package:otzaria/navigation/about_dialog.dart';
import 'package:otzaria/shortcuts/keyboard_shortcuts.dart';
import 'dart:async';
import 'package:otzaria/update/my_updat_widget.dart';
import 'package:otzaria/tools/calendar/ulits/calendar_cubit.dart';
import 'package:otzaria/widgets/ad_popup_dialog.dart';
import 'package:window_manager/window_manager.dart';
import 'package:otzaria/main.dart' show appWindowListener;
import 'package:otzaria/navigation/custom_title_bar.dart';
import 'package:otzaria/migration/sync/background_sync_initializer.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:otzaria/workspaces/bloc/workspace_state.dart';
import 'package:otzaria/widgets/indexing_status_overlay.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/file_sync/file_sync_bloc.dart';
import 'package:otzaria/file_sync/file_sync_event.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_adapter.dart' show buildThemePayload;

class MainWindowScreen extends StatefulWidget {
  const MainWindowScreen({super.key});

  @override
  MainWindowScreenState createState() => MainWindowScreenState();
}

// Global key for accessing MoreScreen
final GlobalKey<MoreScreenState> moreScreenKey = GlobalKey<MoreScreenState>();

class MainWindowScreenState extends State<MainWindowScreen>
    with TickerProviderStateMixin {
  late final PageController pageController;
  late final CalendarCubit _calendarCubit;
  late final SettingsScreenController _settingsScreenController;
  Orientation? _previousOrientation;
  int _currentPageIndex = 0;

  // Keep the pages list as templates; the actual first page (library)
  // will be built dynamically in build() to allow showing the
  // EmptyLibraryScreen inside the library tab while keeping the
  // rest of the application UI available.
  List<Widget> _pages = [];

  // שמירת הדפים כדי שלא ייבנו מחדש
  Widget? _cachedLibraryPage;
  Widget? _cachedReadingPage;
  Widget? _cachedMorePage;
  Widget? _cachedSettingsPage;

  // שמירת BLoC של EmptyLibrary כדי שלא יאבד את המצב
  EmptyLibraryBloc? _emptyLibraryBloc;

  // שמירת מצב הספרייה הקודם כדי לזהות שינויים
  bool? _previousLibraryEmptyState;

  final StartupWorkGate _startupWorkGate = StartupWorkGate();
  bool _hasCheckedAutoIndex = false;
  bool _hasRestoredFullscreen = false;
  bool _hasStartedFileSync = false;
  // עוקב אחר מצב ההגדרות הקודם לצורך dispatch ספציפי
  SettingsState? _prevSettingsState;
  // עוקב אחר מצב הלוח הקודם לצורך dispatch ספציפי
  CalendarState? _prevCalendarState;

  @override
  void initState() {
    super.initState();
    _calendarCubit = CalendarCubit();
    _settingsScreenController = SettingsScreenController();
    final initialPage = _pageIndexForScreen(
          context.read<NavigationBloc>().state.currentScreen,
        ) ??
        Screen.library.index;
    _currentPageIndex = initialPage;
    pageController = PageController(initialPage: initialPage);

    // הצגת פופאפ פרסומת אחרי 5 שניות
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AdPopupDialog.showIfNeeded(context);

      // רענון plugin calendar events עם scope אמיתי לאחר שה-context מוכן.
      // הטעינה הראשונית ב-_initializeCalendar נקראה בלי workspace/book IDs —
      // כאן אנחנו מתקנים זאת עם ה-state שמזומן כעת.
      if (!mounted) return;
      try {
        final workspaceId = context.read<WorkspaceBloc>().state.activeWorkspaceId;
        final bookId = context.read<TabsBloc>().state.currentTab?.title;
        _calendarCubit.refreshPluginEvents(
          currentWorkspaceId: workspaceId,
          currentBookId: bookId,
        );
      } catch (_) {}
    });

    // Setup fullscreen sync with window manager
    _setupFullscreenSync();

    // Listen to calendar changes for plugin dispatch
    _calendarCubit.stream.listen((state) {
       PluginRuntimeDispatcher.instance.dispatchEvent('calendar.date_changed', {
          'date': state.selectedGregorianDate.toIso8601String(),
       });
    });

    // NOTE: Background sync is now triggered by LibraryBloc listener
    // (see MultiBlocListener) to avoid DB lock contention during library loading.
  }

  /// Trigger FileSyncBloc to start syncing AFTER the library is loaded.
  /// Runs only once per app session (guard prevents re-triggering on RefreshLibrary).
  void _startFileSync() {
    if (_hasStartedFileSync) return;
    _hasStartedFileSync = true;

    final isAutoSync =
        Settings.getValue<bool>(SettingsRepository.keyAutoSync) ?? true;
    final settingsState = context.read<SettingsBloc>().state;
    if (isAutoSync && settingsState.canUseSoftwareAndBookUpdates) {
      try {
        context.read<FileSyncBloc>().add(const StartSync());
      } catch (e) {
        debugPrint('Could not start file sync: $e');
      }
    }
  }

  /// Initialize background file sync AFTER library is loaded.
  /// This avoids DB lock contention that caused 17s delays.
  void _initializeBackgroundSync() {
    BackgroundSyncInitializer.initializeAfterDelay(
      delaySeconds: 2, // Small delay to let UI settle after library load
      onComplete: (result) {
        if (!mounted) return;
        if (result.addedBooks > 0 ||
            result.updatedBooks > 0 ||
            result.addedLinks > 0) {
          debugPrint('📚 סנכרון קבצים הושלם: ${result.addedBooks} ספרים חדשים, '
              '${result.updatedBooks} עודכנו, ${result.addedLinks} קישורים');

          // Refresh the library browser to show new books
          try {
            context.read<LibraryBloc>().add(RefreshLibrary());
          } catch (e) {
            debugPrint('Could not refresh library: $e');
          }
        }
      },
    );
  }

  void _tryStartDeferredStartupWork() {
    if (!_startupWorkGate.consumeStartPermission()) {
      return;
    }

    _initializeBackgroundSync();
    _startFileSync();
  }

  /// Setup synchronization between window fullscreen state and settings
  void _setupFullscreenSync() {
    if (kIsWeb ||
        (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS)) {
      return;
    }

    // Listen for fullscreen changes from the window manager (e.g., user presses F11 in OS)
    appWindowListener?.onFullscreenChanged = (isFullscreen) {
      if (!mounted) return;
      final settingsBloc = context.read<SettingsBloc>();
      // Only update if the state is different to avoid loops
      if (settingsBloc.state.isFullscreen != isFullscreen) {
        settingsBloc.add(UpdateIsFullscreen(isFullscreen));
      }
    };
  }

  /// Restore fullscreen state from settings when app starts
  Future<void> _restoreFullscreenState(BuildContext context) async {
    if (_hasRestoredFullscreen) return;
    _hasRestoredFullscreen = true;

    if (kIsWeb ||
        (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS)) {
      return;
    }

    final settingsState = context.read<SettingsBloc>().state;
    if (settingsState.isFullscreen) {
      await windowManager.setFullScreen(true);
    }
  }

  void _checkAndStartIndexing(BuildContext context) {
    // Only check once, after settings are loaded
    if (_hasCheckedAutoIndex) return;
    _hasCheckedAutoIndex = true;

    // Check if auto-update is enabled
    if (context.read<SettingsBloc>().state.autoUpdateIndex) {
      DataRepository.instance.library.then((library) {
        if (!mounted || !context.mounted) return;
        context.read<IndexingBloc>().add(StartIndexing(library));
      });
    }
  }

  @override
  void dispose() {
    // Clean up fullscreen callback
    appWindowListener?.onFullscreenChanged = null;
    _calendarCubit.close();
    _emptyLibraryBloc?.close();
    pageController.dispose();
    super.dispose();
  }

  void _handleOrientationChange(BuildContext context, Orientation orientation) {
    if (_previousOrientation != orientation) {
      _previousOrientation = orientation;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        final currentScreen =
            context.read<NavigationBloc>().state.currentScreen;
        final targetPage = _pageIndexForScreen(currentScreen);
        if (targetPage == null) {
          return;
        }

        if (_currentPageIndex != targetPage) {
          setState(() {
            _currentPageIndex = targetPage;
          });
          if (pageController.hasClients) {
            pageController.jumpToPage(targetPage);
          }
        }
      });
    }
  }

  /// ודאו שה-PageView מסונכרן למצב הניווט הנוכחי גם אם בחרו שוב באותו יעד.
  Future<void> _syncPageWithState() async {
    if (!mounted || !pageController.hasClients) return;
    final currentScreen = context.read<NavigationBloc>().state.currentScreen;
    final targetPage = _pageIndexForScreen(currentScreen);
    if (targetPage == null) return;
    if (_currentPageIndex == targetPage) return;

    setState(() {
      _currentPageIndex = targetPage;
    });
    pageController.jumpToPage(targetPage);
  }

  List<NavigationDestination> _buildNavigationDestinations() {
    String formatShortcut(String shortcut) => shortcut.toUpperCase();

    final libraryShortcut =
        Settings.getValue<String>('key-shortcut-open-library-browser') ??
            'ctrl+l';
    final findShortcut =
        Settings.getValue<String>('key-shortcut-open-find-ref') ?? 'ctrl+o';
    final browseShortcut =
        Settings.getValue<String>('key-shortcut-open-reading-screen') ??
            'ctrl+r';
    final searchShortcut =
        Settings.getValue<String>('key-shortcut-open-new-search') ?? 'ctrl+q';

    return [
      NavigationDestination(
        tooltip: '',
        icon: Tooltip(
          preferBelow: false,
          message: formatShortcut(libraryShortcut),
          child: const Icon(FluentIcons.library_24_regular),
        ),
        label: 'ספרייה',
      ),
      NavigationDestination(
        tooltip: '',
        icon: Tooltip(
          preferBelow: false,
          message: formatShortcut(findShortcut),
          child: const Icon(FluentIcons.book_search_24_regular),
        ),
        label: 'איתור',
      ),
      NavigationDestination(
        tooltip: '',
        icon: Tooltip(
          preferBelow: false,
          message: formatShortcut(browseShortcut),
          child: const Icon(FluentIcons.book_open_24_regular),
        ),
        label: 'עיון',
      ),
      NavigationDestination(
        tooltip: '',
        icon: Tooltip(
          preferBelow: false,
          message: formatShortcut(searchShortcut),
          child: const Icon(FluentIcons.search_24_regular),
        ),
        label: 'חיפוש',
      ),
      NavigationDestination(
        tooltip: '',
        icon: Tooltip(
          preferBelow: false,
          message: formatShortcut(
            Settings.getValue<String>('key-shortcut-open-more') ?? 'ctrl+m',
          ),
          child: const Icon(FluentIcons.apps_24_regular),
        ),
        label: 'כלים',
      ),
      NavigationDestination(
        tooltip: '',
        icon: Tooltip(
          preferBelow: false,
          message: formatShortcut(
            Settings.getValue<String>('key-shortcut-open-settings') ??
                'ctrl+comma',
          ),
          child: const Icon(FluentIcons.settings_24_regular),
        ),
        label: 'הגדרות',
      ),
      NavigationDestination(
        icon: Icon(FluentIcons.info_24_regular),
        label: 'אודות',
      ),
    ];
  }

  void _handleNavigationChange(
    BuildContext context,
    NavigationState state,
  ) async {
    if (!mounted || !context.mounted) {
      return;
    }

    final targetPage = _pageIndexForScreen(state.currentScreen);
    if (targetPage != null && _currentPageIndex != targetPage) {
      setState(() {
        _currentPageIndex = targetPage;
      });
      // מעבר עם אנימציה
      if (pageController.hasClients) {
        pageController.animateToPage(
          targetPage,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    }

    if (state.currentScreen == Screen.library) {
      context.read<FocusRepository>().requestLibrarySearchFocus(
            selectAll: true,
          );
    } else if (state.currentScreen == Screen.more) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          moreScreenKey.currentState?.requestActiveTabFocus();
        }
      });
    } else if (state.currentScreen == Screen.reading) {
      // בקשת focus לתוכן הספר כשעוברים למסך עיון
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<FocusRepository>().requestBookContentFocus();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<NavigationBloc, NavigationState>(
          listenWhen: (previous, current) =>
              previous.currentScreen != current.currentScreen,
          listener: (context, state) {
            PluginRuntimeDispatcher.instance.dispatchEvent('navigation.changed', {
              'screen': state.currentScreen.name,
            });
            _handleNavigationChange(context, state);
          },
        ),
        BlocListener<WorkspaceBloc, WorkspaceState>(
          listenWhen: (previous, current) =>
              previous.activeWorkspaceId != current.activeWorkspaceId ||
              (previous.isLoading && !current.isLoading),
          listener: (context, state) {
            PluginRuntimeDispatcher.instance.dispatchEvent('workspace.changed', {
              'workspaceId': state.activeWorkspaceId,
            });
            // עדכון שם שולחן העבודה הנוכחי ב-HistoryBloc
            final currentId = state.activeWorkspaceId;
            if (currentId != null) {
              final workspace =
                  state.workspaces.firstWhere((w) => w.id == currentId);
              context.read<HistoryBloc>().add(
                    SetCurrentWorkspaceName(workspace.name),
                  );
            }
          },
        ),
        BlocListener<LibraryBloc, LibraryState>(
          listenWhen: (previous, current) =>
              previous.isLoading &&
              !current.isLoading &&
              current.library != null,
          listener: (context, state) {
            _startupWorkGate.markLibraryLoaded();
            _tryStartDeferredStartupWork();
          },
        ),
        BlocListener<IndexingBloc, IndexingState>(
          listenWhen: (previous, current) =>
              (previous is IndexingInProgress) !=
              (current is IndexingInProgress),
          listener: (context, state) {
            _startupWorkGate.markIndexingRunning(
              state is IndexingInProgress,
            );
            _tryStartDeferredStartupWork();
          },
        ),
        BlocListener<SettingsBloc, SettingsState>(
          listenWhen: (previous, current) {
            // fire on first load or any change to plugin-visible settings
            if (previous == SettingsState.initial() && current != SettingsState.initial()) return true;
            return previous.isDarkMode != current.isDarkMode
                || previous.followSystemTheme != current.followSystemTheme
                || previous.seedColor != current.seedColor
                || previous.darkSeedColor != current.darkSeedColor
                || previous.fontSize != current.fontSize
                || previous.fontFamily != current.fontFamily
                || previous.commentatorsFontFamily != current.commentatorsFontFamily
                || previous.commentatorsFontSize != current.commentatorsFontSize
                || previous.lineHeight != current.lineHeight
                || previous.autoUpdateIndex != current.autoUpdateIndex
                || previous.showTeamim != current.showTeamim
                || previous.defaultRemoveNikud != current.defaultRemoveNikud
                || previous.removeNikudFromTanach != current.removeNikudFromTanach
                || previous.replaceHolyNames != current.replaceHolyNames
                || previous.libraryViewMode != current.libraryViewMode
                || previous.alignTabsToRight != current.alignTabsToRight
                || previous.copyWithHeaders != current.copyWithHeaders
                || previous.copyHeaderFormat != current.copyHeaderFormat;
          },
          listener: (context, current) {
            final previous = _prevSettingsState ?? SettingsState.initial();
            _prevSettingsState = current;

            // --- settings.changed: one event per changed key (allowlist only) ---
            void dispatch(String key, dynamic value) {
              PluginRuntimeDispatcher.instance.dispatchEvent(
                  'settings.changed', {'key': key, 'newValue': value});
            }

            if (previous.isDarkMode != current.isDarkMode) {
              dispatch(SettingsRepository.keyDarkMode, current.isDarkMode);
            }
            if (previous.followSystemTheme != current.followSystemTheme) {
              dispatch(SettingsRepository.keyFollowSystemTheme, current.followSystemTheme);
            }
            if (previous.seedColor != current.seedColor) {
              dispatch(SettingsRepository.keySwatchColor, current.seedColor.toARGB32().toRadixString(16));
            }
            if (previous.darkSeedColor != current.darkSeedColor) {
              dispatch(SettingsRepository.keyDarkSwatchColor, current.darkSeedColor.toARGB32().toRadixString(16));
            }
            if (previous.fontSize != current.fontSize) {
              dispatch(SettingsRepository.keyFontSize, current.fontSize);
            }
            if (previous.fontFamily != current.fontFamily) {
              dispatch(SettingsRepository.keyFontFamily, current.fontFamily);
            }
            if (previous.commentatorsFontFamily != current.commentatorsFontFamily) {
              dispatch(SettingsRepository.keyCommentatorsFontFamily, current.commentatorsFontFamily);
            }
            if (previous.commentatorsFontSize != current.commentatorsFontSize) {
              dispatch(SettingsRepository.keyCommentatorsFontSize, current.commentatorsFontSize);
            }
            if (previous.lineHeight != current.lineHeight) {
              dispatch(SettingsRepository.keyLineHeight, current.lineHeight);
            }
            if (previous.showTeamim != current.showTeamim) {
              dispatch(SettingsRepository.keyShowTeamim, current.showTeamim);
            }
            if (previous.defaultRemoveNikud != current.defaultRemoveNikud) {
              dispatch(SettingsRepository.keyDefaultNikud, current.defaultRemoveNikud);
            }
            if (previous.removeNikudFromTanach != current.removeNikudFromTanach) {
              dispatch(SettingsRepository.keyRemoveNikudFromTanach, current.removeNikudFromTanach);
            }
            if (previous.replaceHolyNames != current.replaceHolyNames) {
              dispatch(SettingsRepository.keyReplaceHolyNames, current.replaceHolyNames);
            }
            if (previous.libraryViewMode != current.libraryViewMode) {
              dispatch(SettingsRepository.keyLibraryViewMode, current.libraryViewMode);
            }
            if (previous.alignTabsToRight != current.alignTabsToRight) {
              dispatch(SettingsRepository.keyAlignTabsToRight, current.alignTabsToRight);
            }
            if (previous.copyWithHeaders != current.copyWithHeaders) {
              dispatch(SettingsRepository.keyCopyWithHeaders, current.copyWithHeaders);
            }
            if (previous.copyHeaderFormat != current.copyHeaderFormat) {
              dispatch(SettingsRepository.keyCopyHeaderFormat, current.copyHeaderFormat);
            }

            // --- theme.changed: only when visual theme changes ---
            final isThemeChange = previous.isDarkMode != current.isDarkMode
                || previous.followSystemTheme != current.followSystemTheme
                || previous.seedColor != current.seedColor
                || previous.darkSeedColor != current.darkSeedColor
                || previous.fontSize != current.fontSize
                || previous.fontFamily != current.fontFamily
                || previous.lineHeight != current.lineHeight
                || previous.commentatorsFontFamily != current.commentatorsFontFamily
                || previous.commentatorsFontSize != current.commentatorsFontSize;
            if (isThemeChange) {
              final themePayload = buildThemePayload(context);
              PluginRuntimeDispatcher.instance.dispatchEvent('theme.changed', themePayload);
            }

            // --- internal app logic ---
            _checkAndStartIndexing(context);
            _startupWorkGate.markIndexingDecisionResolved(
              expectIndexing: current.autoUpdateIndex,
            );
            _tryStartDeferredStartupWork();
            _restoreFullscreenState(context);
          },
        ),
        BlocListener<TabsBloc, TabsState>(
          listenWhen: (previous, current) => previous.currentTab != current.currentTab,
          listener: (context, state) {
            final currentTab = state.currentTab;
            if (currentTab != null) {
              int tabIndex = 0;
              if (currentTab is TextBookTab) tabIndex = currentTab.index;
              if (currentTab is PdfBookTab) tabIndex = currentTab.pageNumber;
              PluginRuntimeDispatcher.instance.dispatchEvent('reader.current_book_changed', {
                'book': currentTab.title,
                'index': tabIndex,
              });
            }
          },
        ),
        // settings.changed עבור selectedCity ו-calendarType —
        // שדות אלה נמצאים ב-CalendarState ולא ב-SettingsState
        BlocListener<CalendarCubit, CalendarState>(
          listenWhen: (previous, current) =>
              previous.selectedCity != current.selectedCity ||
              previous.calendarType != current.calendarType,
          listener: (context, current) {
            final previous = _prevCalendarState;
            _prevCalendarState = current;
            if (previous == null) return;
            if (previous.selectedCity != current.selectedCity) {
              PluginRuntimeDispatcher.instance.dispatchEvent('settings.changed', {
                'key': SettingsRepository.keySelectedCity,
                'newValue': current.selectedCity,
              });
            }
            if (previous.calendarType != current.calendarType) {
              PluginRuntimeDispatcher.instance.dispatchEvent('settings.changed', {
                'key': SettingsRepository.keyCalendarType,
                'newValue': current.calendarType.toString(),
              });
            }
          },
        ),
        // רענון לוח כשמשתנה הספר הפתוח (book-scope events)
        BlocListener<TabsBloc, TabsState>(
          listenWhen: (previous, current) =>
              previous.currentTab?.title != current.currentTab?.title,
          listener: (context, state) {
            final bookId = state.currentTab?.title;
            final workspaceId = context.read<WorkspaceBloc>().state.activeWorkspaceId;
            _calendarCubit.refreshPluginEvents(
              currentBookId: bookId,
              currentWorkspaceId: workspaceId,
            );
          },
        ),
        // רענון לוח כשמשתנה ה-workspace (workspace-scope events)
        BlocListener<WorkspaceBloc, WorkspaceState>(
          listenWhen: (previous, current) =>
              previous.activeWorkspaceId != current.activeWorkspaceId,
          listener: (context, state) {
            final workspaceId = state.activeWorkspaceId;
            final bookId = context.read<TabsBloc>().state.currentTab?.title;
            _calendarCubit.refreshPluginEvents(
              currentWorkspaceId: workspaceId,
              currentBookId: bookId,
            );
          },
        ),
        BlocListener<PluginSystemBloc, PluginSystemState>(
          listenWhen: (previous, current) => false, // Only interested in permission changed, wait, plugin system state doesn't track this perfectly yet.
          listener: (context, state) {},
        ),
      ],
      child: BlocProvider.value(
        value: _calendarCubit,
        child: BlocBuilder<NavigationBloc, NavigationState>(
          builder: (context, state) {
            // Build the pages list here so we can inject the EmptyLibraryScreen
            // into the library page while keeping the rest of the app visible.
            // נבנה את הדפים רק פעם אחת ונשמור אותם
            // אם מצב הספרייה השתנה, נבנה מחדש את דף הספרייה
            if (_cachedLibraryPage == null ||
                state.isLibraryEmpty !=
                    (_cachedLibraryPage is EmptyLibraryScreen) ||
                _previousLibraryEmptyState != state.isLibraryEmpty) {
              if (state.isLibraryEmpty) {
                // יצירת BLoC פעם אחת אם עדיין לא קיים
                _emptyLibraryBloc ??= EmptyLibraryBloc();
                _cachedLibraryPage = EmptyLibraryScreen(
                  bloc: _emptyLibraryBloc,
                  onLibraryLoaded: () {
                    context.read<NavigationBloc>().refreshLibrary();
                  },
                );
              } else {
                // אם הספרייה כבר לא ריקה, נסגור את ה-BLoC
                _emptyLibraryBloc?.close();
                _emptyLibraryBloc = null;
                _cachedLibraryPage = const LibraryBrowser();
              }
              _previousLibraryEmptyState = state.isLibraryEmpty;
            }

            _cachedReadingPage ??= const ReadingScreen();
            _cachedMorePage ??= MoreScreen(key: moreScreenKey);
            _cachedSettingsPage ??=
                MySettingsScreen(controller: _settingsScreenController);

            _pages = [
              _cachedLibraryPage!,
              _cachedReadingPage!,
              _cachedMorePage!,
              _cachedSettingsPage!,
            ];

            return SafeArea(
              child: KeyboardShortcuts(
                child: MyUpdatWidget(
                  child: Scaffold(
                    resizeToAvoidBottomInset: false,
                    body: Stack(
                      children: [
                        Column(
                          children: [
                            const CustomTitleBar(),
                            Expanded(
                              child: OrientationBuilder(
                                builder: (context, orientation) {
                                  _handleOrientationChange(
                                      context, orientation);

                                  final pageView = PageView(
                                    controller: pageController,
                                    scrollDirection:
                                        orientation == Orientation.landscape
                                            ? Axis.vertical
                                            : Axis.horizontal,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    children: _pages,
                                  );

                                  if (orientation == Orientation.landscape) {
                                    return Row(
                                      children: [
                                        SizedBox.fromSize(
                                          size: const Size.fromWidth(74),
                                          child: Column(
                                            children: [
                                              Expanded(
                                                child: Material(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .surface,
                                                  child: LayoutBuilder(
                                                    builder:
                                                        (context, constraints) {
                                                      // חישוב גובה משוער לכל הכפתורים
                                                      const buttonHeight =
                                                          60.0; // גובה משוער לכפתור + padding
                                                      final totalButtonsHeight =
                                                          7 * buttonHeight;
                                                      final minSpacerHeight =
                                                          20.0;
                                                      final needsScroll =
                                                          totalButtonsHeight +
                                                                  minSpacerHeight >
                                                              constraints
                                                                  .maxHeight;

                                                      if (needsScroll) {
                                                        // אם אין מספיק מקום, השתמש בגלילה
                                                        return SingleChildScrollView(
                                                          child: Column(
                                                            children: [
                                                              for (int i = 0;
                                                                  i < 7;
                                                                  i++)
                                                                _buildNavButton(
                                                                  context,
                                                                  _buildNavigationDestinations()[
                                                                      i],
                                                                  i,
                                                                  state
                                                                      .currentScreen,
                                                                ),
                                                            ],
                                                          ),
                                                        );
                                                      } else {
                                                        // אם יש מספיק מקום, השתמש ב-Spacer
                                                        return Column(
                                                          children: [
                                                            // כפתורים עליונים
                                                            for (int i = 0;
                                                                i < 5;
                                                                i++)
                                                              _buildNavButton(
                                                                context,
                                                                _buildNavigationDestinations()[
                                                                    i],
                                                                i,
                                                                state
                                                                    .currentScreen,
                                                              ),
                                                            // רווח גמיש
                                                            const Spacer(),
                                                            // כפתורים תחתונים
                                                            for (int i = 5;
                                                                i < 7;
                                                                i++)
                                                              _buildNavButton(
                                                                context,
                                                                _buildNavigationDestinations()[
                                                                    i],
                                                                i,
                                                                state
                                                                    .currentScreen,
                                                              ),
                                                          ],
                                                        );
                                                      }
                                                    },
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const VerticalDivider(
                                            thickness: 1, width: 1),
                                        Expanded(child: pageView),
                                      ],
                                    );
                                  } else {
                                    return Column(
                                      children: [
                                        Expanded(child: pageView),
                                        NavigationBar(
                                          destinations:
                                              _buildNavigationDestinations(),
                                          selectedIndex: _getSelectedIndex(
                                            state.currentScreen,
                                          ),
                                          onDestinationSelected: (index) async {
                                            // אם בחרו שוב באותו היעד – רק סנכרנו את ה-PageView למסך
                                            final currentIndex =
                                                _getSelectedIndex(
                                                    state.currentScreen);
                                            if (index == currentIndex &&
                                                index != Screen.search.index &&
                                                index != Screen.find.index) {
                                              // סנכרון ידני – שימושי כאשר מסיבה כלשהי ה-PageView סטה מהמצב
                                              await _syncPageWithState();
                                              return;
                                            }
                                            if (index == Screen.search.index) {
                                              _handleSearchTabOpen(context);
                                            } else if (index ==
                                                Screen.find.index) {
                                              _handleFindRefOpen(context);
                                            } else if (index ==
                                                Screen.about.index) {
                                              showDialog(
                                                context: context,
                                                builder: (context) =>
                                                    const AboutDialogWidget(),
                                              );
                                            } else {
                                              context
                                                  .read<NavigationBloc>()
                                                  .add(
                                                    NavigateToScreen(
                                                        Screen.values[index]),
                                                  );
                                            }
                                            if (index == Screen.library.index) {
                                              context
                                                  .read<FocusRepository>()
                                                  .requestLibrarySearchFocus(
                                                    selectAll: true,
                                                  );
                                            }
                                          },
                                        ),
                                      ],
                                    );
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        IndexingStatusOverlay(
                          onTap: _openIndexingSettings,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _openIndexingSettings() {
    _settingsScreenController.openTab(SettingsTab.library);
    context.read<NavigationBloc>().add(
          const NavigateToScreen(Screen.settings),
        );
  }

  int? _pageIndexForScreen(Screen screen) {
    switch (screen) {
      case Screen.library:
        return 0;
      case Screen.reading:
      case Screen.search:
        return 1;
      case Screen.more:
        return 2;
      case Screen.settings:
        return 3;
      case Screen.find:
      case Screen.about:
        return null;
    }
  }

  void _handleSearchTabOpen(BuildContext context) {
    final navigationBloc = context.read<NavigationBloc>();

    showDialog(
      context: context,
      builder: (context) => const SearchDialog(existingTab: null),
    ).then((_) {
      // אחרי סגירת הדיאלוג, אם אנחנו במסך reading/search, נוודא שהמצב מסונכרן
      if (!mounted) return;
      final currentScreen = navigationBloc.state.currentScreen;
      if (currentScreen == Screen.reading || currentScreen == Screen.search) {
        _syncPageWithState();
      }
    });
  }

  void _handleFindRefOpen(BuildContext context) {
    final navigationBloc = context.read<NavigationBloc>();

    showDialog(
      context: context,
      builder: (context) => FindRefDialog(),
    ).then((_) {
      // אחרי סגירת הדיאלוג, אם אנחנו במסך reading, נוודא שהמצב מסונכרן
      if (!mounted) return;
      final currentScreen = navigationBloc.state.currentScreen;
      if (currentScreen == Screen.reading || currentScreen == Screen.search) {
        _syncPageWithState();
      }
    });
  }

  int _getSelectedIndex(Screen currentScreen) {
    // מיפוי מחדש של האינדקסים כיון שהסרנו את דף האיתור
    switch (currentScreen) {
      case Screen.library:
        return 0;
      case Screen.find:
        return -1; // לא נבחר
      case Screen.reading:
        return 2;
      case Screen.search:
        return 3;
      case Screen.more:
        return 4;
      case Screen.settings:
        return 5;
      case Screen.about:
        return 6;
    }
  }

  Widget _buildNavButton(
    BuildContext context,
    NavigationDestination destination,
    int index,
    Screen currentScreen,
  ) {
    final isSelected = _getSelectedIndex(currentScreen) == index;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: 74,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: () async {
              // אם בחרו שוב באותו היעד – רק סנכרנו את ה-PageView למסך
              final currentIndex = _getSelectedIndex(currentScreen);
              if (index == currentIndex &&
                  index != Screen.search.index &&
                  index != Screen.find.index) {
                await _syncPageWithState();
                return;
              }
              if (index == Screen.search.index) {
                _handleSearchTabOpen(context);
              } else if (index == Screen.find.index) {
                _handleFindRefOpen(context);
              } else if (index == Screen.about.index) {
                showDialog(
                  context: context,
                  builder: (context) => const AboutDialogWidget(),
                );
              } else {
                context.read<NavigationBloc>().add(
                      NavigateToScreen(Screen.values[index]),
                    );
              }
              if (index == Screen.library.index) {
                context.read<FocusRepository>().requestLibrarySearchFocus(
                      selectAll: true,
                    );
              }
            },
            icon: IconTheme(
              data: IconThemeData(
                color: isSelected
                    ? colorScheme.onSecondaryContainer
                    : colorScheme.onSurfaceVariant,
                size: 24,
              ),
              child: destination.icon,
            ),
            style: IconButton.styleFrom(
              backgroundColor: isSelected
                  ? colorScheme.secondaryContainer
                  : Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              minimumSize: const Size(56, 25),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            destination.label,
            style: TextStyle(
              fontSize: 11,
              color: isSelected
                  ? colorScheme.onSecondaryContainer
                  : colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class KeepAlivePage extends StatefulWidget {
  final Widget child;

  const KeepAlivePage({super.key, required this.child});

  @override
  State<KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
