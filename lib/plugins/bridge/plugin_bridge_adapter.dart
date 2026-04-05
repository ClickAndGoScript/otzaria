import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/utils/book_open_coordinator.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/tools/calendar/ulits/calendar_cubit.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';

// ===================================================================
// Spec-compliant allowlist for settings.get/getMany
// keys a plugin CAN read (from plugin_system_plan.md#L954)
// ===================================================================
const _settingsAllowlist = {
  SettingsRepository.keyDarkMode,
  SettingsRepository.keyFollowSystemTheme,
  SettingsRepository.keySwatchColor,
  SettingsRepository.keyDarkSwatchColor,
  SettingsRepository.keyFontSize,
  SettingsRepository.keyFontFamily,
  SettingsRepository.keyCommentatorsFontFamily,
  SettingsRepository.keyCommentatorsFontSize,
  SettingsRepository.keyLineHeight,
  SettingsRepository.keySelectedCity,
  SettingsRepository.keyCalendarType,
  SettingsRepository.keyShowTeamim,
  SettingsRepository.keyDefaultNikud,
  SettingsRepository.keyRemoveNikudFromTanach,
  SettingsRepository.keyReplaceHolyNames,
  SettingsRepository.keyLibraryViewMode,
  SettingsRepository.keyAlignTabsToRight,
  SettingsRepository.keyCopyWithHeaders,
  SettingsRepository.keyCopyHeaderFormat,
};

// keys a plugin CANNOT read even if attempted
const _settingsBlocklist = {
  SettingsRepository.keyProtectedModePasswordHash,
  SettingsRepository.keyGoogleCalendarClientSecret,
  SettingsRepository.keyGoogleCalendarCredentialsJson,
  SettingsRepository.keyDbEffectivePath,
  SettingsRepository.keyLibraryPath,
  SettingsRepository.keyIndexPath,
  SettingsRepository.keyBackupPath,
  SettingsRepository.keyHebrewBooksPath,
  SettingsRepository.keyErrorReportSenderEmail,
};

// ===================================================================
// Helper: build full colorScheme + typography from Flutter theme
// ===================================================================
Map<String, dynamic> buildThemePayload(BuildContext context) {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  final isDark = theme.brightness == Brightness.dark;
  String hex(Color c) =>
      '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';

  final fontFamily =
      Settings.getValue<String>(SettingsRepository.keyFontFamily) ??
          'Frank Ruhl Libre';
  final commentatorsFontFamily =
      Settings.getValue<String>(SettingsRepository.keyCommentatorsFontFamily) ??
          'Shofar';
  final fontSize =
      Settings.getValue<double>(SettingsRepository.keyFontSize) ?? 25.0;
  final commentatorsFontSize =
      Settings.getValue<double>(SettingsRepository.keyCommentatorsFontSize) ??
          22.0;
  final lineHeight =
      Settings.getValue<double>(SettingsRepository.keyLineHeight) ?? 1.5;

  return {
    'mode': isDark ? 'dark' : 'light',
    'colorScheme': {
      'primary': hex(cs.primary),
      'onPrimary': hex(cs.onPrimary),
      'secondary': hex(cs.secondary),
      'onSecondary': hex(cs.onSecondary),
      'surface': hex(cs.surface),
      'onSurface': hex(cs.onSurface),
      'surfaceContainerHighest': hex(cs.surfaceContainerHighest),
      'error': hex(cs.error),
      'onError': hex(cs.onError),
      'outline': hex(cs.outline),
    },
    'typography': {
      'fontFamily': fontFamily,
      'fontSize': fontSize,
      'lineHeight': lineHeight,
      'commentatorsFontFamily': commentatorsFontFamily,
      'commentatorsFontSize': commentatorsFontSize,
    },
  };
}

class PluginBridgeDependencies {
  final HistoryBloc historyBloc;
  final TabsBloc tabsBloc;
  final NavigationBloc navigationBloc;
  final CalendarCubit calendarCubit;
  final WorkspaceBloc workspaceBloc;
  final SearchRepository searchRepository;
  final PersonalNotesRepository personalNotesRepository;
  final BookOpenCoordinator bookOpenCoordinator;
  final Map<String, dynamic> Function() themePayloadBuilder;
  final Future<bool> Function({
    required String title,
    required String content,
  }) showConfirmDialog;
  final Future<bool> Function({
    required String title,
    required String content,
    required String subtitle,
  }) showWarningDialog;

  const PluginBridgeDependencies({
    required this.historyBloc,
    required this.tabsBloc,
    required this.navigationBloc,
    required this.calendarCubit,
    required this.workspaceBloc,
    required this.searchRepository,
    required this.personalNotesRepository,
    required this.bookOpenCoordinator,
    required this.themePayloadBuilder,
    required this.showConfirmDialog,
    required this.showWarningDialog,
  });
}

// ===================================================================
// Bridge Adapter - strict 1:1 with plugin_system_plan.md
// ===================================================================
class PluginBridgeAdapter {
  final InstalledPlugin plugin;
  final PluginRegistryRepository _pluginRepo;
  final PluginBridgeDependencies _dependencies;

  PluginBridgeAdapter(
    this.plugin, {
    required PluginBridgeDependencies dependencies,
    PluginRegistryRepository? pluginRepository,
  })  : _dependencies = dependencies,
        _pluginRepo = pluginRepository ?? PluginRegistryRepository();

  Future<dynamic> execute(
      String domain, String action, Map<String, dynamic> args) async {
    switch (domain) {
      case 'app':
        return await _handleApp(action, args);
      case 'library':
        return await _handleLibrary(action, args);
      case 'search':
        return await _handleSearch(action, args);
      case 'reader':
        return await _handleReader(action, args);
      case 'navigation':
        return await _handleNavigation(action, args);
      case 'notes':
        return await _handleNotes(action, args);
      case 'ui':
        return await _handleUi(action, args);
      case 'storage':
        return await _handleStorage(action, args);
      case 'settings':
        return await _handleSettings(action, args);
      case 'calendar':
        return await _handleCalendar(action, args);
      case 'publishedData':
        return await _handlePublishedData(action, args);
      default:
        throw Exception("Unknown domain: $domain");
    }
  }

  // ----------------------------------------------------------------
  // app.*
  // ----------------------------------------------------------------
  Future<dynamic> _handleApp(String action, Map<String, dynamic> args) async {
    switch (action) {
      case 'getInfo':
        final packageInfo = await PackageInfo.fromPlatform();
        return {
          'version': packageInfo.version,
          'buildNumber': packageInfo.buildNumber,
          'platform': Platform.operatingSystem,
        };
      case 'getTheme':
        return _dependencies.themePayloadBuilder();
      case 'getLocale':
        return {'locale': 'he-IL', 'textDirection': 'rtl'};
      default:
        throw Exception("Unknown action in app: $action");
    }
  }

  // ----------------------------------------------------------------
  // library.*
  // ----------------------------------------------------------------
  Future<dynamic> _handleLibrary(
      String action, Map<String, dynamic> args) async {
    final library = await DataRepository.instance.library;
    switch (action) {
      case 'findBooks':
        final query = args['query']?.toString().toLowerCase() ?? '';
        final limit = args['limit'] as int? ?? 20;
        final allBooks = library.getAllBooks();
        return allBooks
            .where((b) => b.title.toLowerCase().contains(query))
            .take(limit)
            // spec: returns [{bookId, title, author?, topics?}]
            .map((b) => {
                  'bookId': b.title, // title is the stable ID in otzaria
                  'title': b.title,
                })
            .toList();
      case 'getBookMetadata':
        // spec: accepts bookId (= title in otzaria) or title for back-compat
        final bookId = (args['bookId'] ?? args['title']) as String?;
        if (bookId == null) throw Exception('bookId required');
        final allBooks = library.getAllBooks();
        final book = allBooks
            .cast<dynamic>()
            .firstWhere((b) => b?.title == bookId, orElse: () => null);
        if (book == null) return null;
        return {
          'bookId': book.title,
          'title': book.title,
          'topics': book.topics
        };
      case 'listRecentBooks':
        final historyState = _dependencies.historyBloc.state;
        if (historyState is! HistoryLoaded) return [];
        return historyState.history
            .where((b) => !b.isSearch)
            .take(20)
            .map((b) =>
                {'bookId': b.book.title, 'title': b.book.title, 'ref': b.ref})
            .toList();
      case 'getBookContent':
        final bookId = (args['bookId'] ?? args['title']) as String?;
        if (bookId == null) throw Exception('bookId required');
        final rawText = await DataRepository.instance.getBookText(bookId);
        final limit = args['limit'] as int? ?? 1000;
        final offset = args['offset'] as int? ?? 0;
        final section = args['section'] as String?;
        int startIndex = offset;
        if (section != null && section.isNotEmpty) {
          final idx = rawText.indexOf(section);
          if (idx >= 0) startIndex = idx;
        }
        final clampedLimit = limit > 5000 ? 5000 : limit;
        final end = (startIndex + clampedLimit).clamp(0, rawText.length);
        return rawText.substring(startIndex.clamp(0, rawText.length), end);
      case 'getBookToc':
        final bookId = (args['bookId'] ?? args['title']) as String?;
        if (bookId == null) throw Exception('bookId required');
        final allBooks = library.getAllBooks();
        final book = allBooks
            .cast<dynamic>()
            .firstWhere((b) => b?.title == bookId, orElse: () => null);
        if (book != null && book is TextBook) {
          final toc = await book.tableOfContents;
          return toc
              .map((e) => {'text': e.text, 'index': e.index, 'level': e.level})
              .toList();
        }
        return [];
      default:
        throw Exception('Unknown action in library: $action');
    }
  }

  // ----------------------------------------------------------------
  // search.*
  // ----------------------------------------------------------------
  Future<dynamic> _handleSearch(
      String action, Map<String, dynamic> args) async {
    switch (action) {
      case 'fullText':
        final query = args['query'] as String?;
        final limit = args['limit'] as int? ?? 50;
        if (query == null || query.isEmpty) return [];
        final results =
            await _dependencies.searchRepository.searchTexts(query, [], limit);
        return results
            .map((r) =>
                {'book': r.title, 'text': r.text, 'index': r.segment.toInt()})
            .toList();
      default:
        throw Exception("Unknown action in search: $action");
    }
  }

  // ----------------------------------------------------------------
  // reader.*
  // ----------------------------------------------------------------
  Future<dynamic> _handleReader(
      String action, Map<String, dynamic> args) async {
    switch (action) {
      case 'openBook':
        // spec: openBook({ bookId, index?, searchQuery? })
        // also accepts legacy 'title' for back-compat
        final bookId = (args['bookId'] ?? args['title']) as String?;
        final index = args['index'] as int? ?? 0;
        final searchQuery = args['searchQuery'] as String? ?? '';
        if (bookId == null) throw Exception('bookId required');
        final allBooks = (await DataRepository.instance.library).getAllBooks();
        final book = allBooks
            .cast<dynamic>()
            .firstWhere((b) => b?.title == bookId, orElse: () => null);
        if (book == null) return false;
        _dependencies.bookOpenCoordinator.openBook(
          book,
          index,
          searchQuery,
          ignoreHistory: true,
        );
        return true;
      case 'openBookAtRef':
        // spec: openBookAtRef({ bookId, ref, index? })
        final bookId = (args['bookId'] ?? args['title']) as String?;
        final ref = args['ref'] as String?;
        int index = args['index'] as int? ?? 0;
        if (bookId == null) throw Exception('bookId required');
        final allBooks = (await DataRepository.instance.library).getAllBooks();
        final book = allBooks
            .cast<dynamic>()
            .firstWhere((b) => b?.title == bookId, orElse: () => null);
        if (book == null) return false;
        if (ref != null && ref.isNotEmpty && book is TextBook) {
          try {
            final toc = await book.tableOfContents;
            final entry = toc.cast<dynamic>().firstWhere(
                  (e) => e?.text != null && e.text.toString().contains(ref),
                  orElse: () => null,
                );
            if (entry != null) index = entry.index as int;
          } catch (_) {}
        }
        _dependencies.bookOpenCoordinator.openBook(
          book,
          index,
          ref ?? '',
          ignoreHistory: true,
        );
        return true;
      case 'getCurrentState':
        final tabsState = _dependencies.tabsBloc.state;
        final currentTab = tabsState.currentTab;
        final openTabs = tabsState.tabs
            .map((t) => {
                  'bookId': t.title,
                  'book': t.title,
                  'index': t is TextBookTab
                      ? t.index
                      : (t is PdfBookTab ? t.pageNumber : 0),
                })
            .toList();
        if (currentTab == null) {
          return {'currentBook': null, 'currentIndex': 0, 'openTabs': openTabs};
        }
        return {
          'currentBook': currentTab.title,
          'currentBookId': currentTab.title,
          'currentIndex': currentTab is TextBookTab
              ? currentTab.index
              : (currentTab is PdfBookTab ? currentTab.pageNumber : 0),
          'openTabs': openTabs,
        };
      default:
        throw Exception('Unknown action in reader: $action');
    }
  }

  // ----------------------------------------------------------------
  // navigation.*
  // ----------------------------------------------------------------
  Future<dynamic> _handleNavigation(
      String action, Map<String, dynamic> args) async {
    switch (action) {
      case 'goTo':
        final target = args['target'] as String?;
        if (target == null) {
          throw Exception("target required");
        }
        Screen? screen;
        switch (target) {
          case 'library':
            screen = Screen.library;
            break;
          case 'reading':
            screen = Screen.reading;
            break;
          case 'more':
            screen = Screen.more;
            break;
          case 'settings':
            screen = Screen.settings;
            break;
          default:
            throw Exception(
                "Invalid navigation target: $target. Valid: library, reading, more, settings");
        }
        _dependencies.navigationBloc.add(NavigateToScreen(screen));
        return true;
      default:
        throw Exception("Unknown action in navigation: $action");
    }
  }

  // ----------------------------------------------------------------
  // notes.*
  // ----------------------------------------------------------------
  Future<dynamic> _handleNotes(String action, Map<String, dynamic> args) async {
    final repo = _dependencies.personalNotesRepository;
    switch (action) {
      case 'list':
        final bookId = args['bookId'] as String?;
        if (bookId == null) throw Exception("bookId required");
        final notes = await repo.loadNotes(bookId);
        return notes
            .map((n) => {
                  'id': n.id,
                  'lineNumber': n.lineNumber,
                  'content': n.content,
                  'contentPlain': n.contentPlain
                })
            .toList();
      case 'getBookNotesSummary':
        final summaries = await repo.listBooksWithNotes();
        return summaries
            .map((s) => {
                  'bookId': s.bookId,
                  'noteCount': s.noteCount,
                  'lastModified': s.lastUpdated.toIso8601String()
                })
            .toList();
      case 'add':
        final bookId = args['bookId'] as String?;
        final lineNumber = args['lineNumber'] as int?;
        final content = args['content'] as String?;
        if (bookId == null || lineNumber == null || content == null) {
          throw Exception("Missing arguments");
        }
        await repo.addNote(
          bookId: bookId,
          lineNumber: lineNumber,
          content: content,
          contentPlain: content,
          contentFormat: PersonalNoteContentFormat.plain,
        );
        return true;
      case 'update':
        final bookId = args['bookId'] as String?;
        final noteId = args['noteId'] as String?;
        final content = args['content'] as String?;
        if (bookId == null || noteId == null || content == null) {
          throw Exception("Missing arguments");
        }
        await repo.updateNote(
            bookId: bookId,
            noteId: noteId,
            content: content,
            contentPlain: content,
            contentFormat: PersonalNoteContentFormat.plain);
        return true;
      case 'delete':
        final bookId = args['bookId'] as String?;
        final noteId = args['noteId'] as String?;
        if (bookId == null || noteId == null) {
          throw Exception("Missing arguments");
        }
        await repo.deleteNote(bookId: bookId, noteId: noteId);
        return true;
      default:
        throw Exception("Unknown action in notes: $action");
    }
  }

  // ----------------------------------------------------------------
  // ui.*
  // ----------------------------------------------------------------
  Future<dynamic> _handleUi(String action, Map<String, dynamic> args) async {
    switch (action) {
      case 'showMessage':
        UiSnack.show(args['message'] as String? ?? '');
        return true;
      case 'showSuccess':
        UiSnack.showSuccess(args['message'] as String? ?? '');
        return true;
      case 'showError':
        UiSnack.showError(args['message'] as String? ?? '');
        return true;
      case 'showConfirm':
        final result = await _dependencies.showConfirmDialog(
          title: args['title'] as String? ?? 'אישור',
          content: args['content'] as String? ?? '',
        );
        return {'confirmed': result};
      case 'showWarning':
        final result = await _dependencies.showWarningDialog(
          title: args['title'] as String? ?? 'אזהרה',
          content: args['content'] as String? ?? '',
          subtitle: args['subtitle'] as String? ?? '',
        );
        return {'confirmed': result};
      default:
        throw Exception("Unknown action in ui: $action");
    }
  }

  // ----------------------------------------------------------------
  // storage.*
  // ----------------------------------------------------------------
  Future<dynamic> _handleStorage(
      String action, Map<String, dynamic> args) async {
    switch (action) {
      case 'get':
        final key = args['key'] as String?;
        if (key == null) throw Exception("key required");
        final value = await _pluginRepo.getKV(plugin.pluginId, 'default', key);
        return value != null ? jsonDecode(value) : null;
      case 'set':
        final key = args['key'] as String?;
        final value = args['value'];
        if (key == null || value == null) {
          throw Exception("key and value required");
        }
        await _pluginRepo.setKV(
            plugin.pluginId, 'default', key, jsonEncode(value));
        return true;
      case 'remove':
        final key = args['key'] as String?;
        if (key == null) throw Exception("key required");
        await _pluginRepo.removeKV(plugin.pluginId, 'default', key);
        return true;
      case 'list':
        return _pluginRepo.listKVKeys(plugin.pluginId, 'default');
      default:
        throw Exception("Unknown action in storage: $action");
    }
  }

  // ----------------------------------------------------------------
  // settings.*
  // ----------------------------------------------------------------
  Future<dynamic> _handleSettings(
      String action, Map<String, dynamic> args) async {
    bool isAllowed(String key) =>
        _settingsAllowlist.contains(key) && !_settingsBlocklist.contains(key);

    switch (action) {
      case 'get':
        final key = args['key'] as String?;
        if (key == null || !isAllowed(key)) return null;
        return Settings.getValue(key);
      case 'getMany':
        final keys = (args['keys'] as List?)?.cast<String>() ?? [];
        final Map<String, dynamic> res = {};
        for (final k in keys) {
          if (isAllowed(k)) res[k] = Settings.getValue(k);
        }
        return res;
      default:
        throw Exception("Unknown action in settings: $action");
    }
  }

  // ----------------------------------------------------------------
  // calendar.*
  // ----------------------------------------------------------------
  Future<dynamic> _handleCalendar(
      String action, Map<String, dynamic> args) async {
    final calendarState = _dependencies.calendarCubit.state;

    switch (action) {
      case 'getSelectedDate':
        return calendarState.selectedGregorianDate.toIso8601String();
      case 'getDailyTimes':
        return calendarState.dailyTimes;
      case 'getHalachicTimes':
        // dailyTimes contains all halachic times (shekia, tzet haochavim, etc.)
        return calendarState.dailyTimes;
      case 'getJewishDate':
        final jd = calendarState.selectedJewishDate;
        return {
          'year': jd.getJewishYear(),
          'month': jd.getJewishMonth(),
          'day': jd.getJewishDayOfMonth(),
          'gregorian': calendarState.selectedGregorianDate.toIso8601String(),
        };
      case 'getEvents':
        final date = args['date'] != null
            ? DateTime.tryParse(args['date'] as String) ??
                calendarState.selectedGregorianDate
            : calendarState.selectedGregorianDate;
        final events = calendarState.events
            .where((e) {
              final eventDate = e.baseGregorianDate;
              return eventDate.year == date.year &&
                  eventDate.month == date.month &&
                  eventDate.day == date.day;
            })
            .map((e) => {
                  'id': e.id,
                  'title': e.title,
                  'date': e.baseGregorianDate.toIso8601String(),
                  'description': e.description,
                })
            .toList();
        return events;
      default:
        throw Exception("Unknown action in calendar: $action");
    }
  }

  // ----------------------------------------------------------------
  // publishedData.*
  // ----------------------------------------------------------------
  Future<dynamic> _handlePublishedData(
      String action, Map<String, dynamic> args) async {
    switch (action) {
      case 'upsert':
        final type = args['type'] as String?;
        final scope = args['scope'] as String? ?? 'global';
        final key = args['key'] as String?;
        final payload = args['payload'];
        if (type == null || key == null || payload == null) {
          throw Exception('type, key, payload required');
        }
        await _pluginRepo.publishRecord(
            plugin.pluginId, type, scope, key, jsonEncode(payload), null);
        // רענון חי של לוח השנה כשמדובר באירוע לוח
        if (type == 'calendar.event') {
          _dependencies.calendarCubit.refreshPluginEvents(
            currentBookId: _currentBookId(),
            currentWorkspaceId: _currentWorkspaceId(),
          );
        }
        return true;
      case 'remove':
        final type = args['type'] as String?;
        final scope = args['scope'] as String? ?? 'global';
        final key = args['key'] as String?;
        if (type == null || key == null) {
          throw Exception('type and key required');
        }
        await _pluginRepo.unpublishRecord(plugin.pluginId, type, scope, key);
        // רענון חי של לוח השנה
        if (type == 'calendar.event') {
          _dependencies.calendarCubit.refreshPluginEvents(
            currentBookId: _currentBookId(),
            currentWorkspaceId: _currentWorkspaceId(),
          );
        }
        return true;
      case 'listOwn':
        final rows =
            await _pluginRepo.getPluginPublishedRecords(plugin.pluginId);
        return rows
            .map((record) => {
                  'type': record.type,
                  'scope': record.scope,
                  'key': record.key,
                  'payload': record.decodedPayload,
                })
            .toList();
      default:
        throw Exception("Unknown action in publishedData: $action");
    }
  }

  // ----------------------------------------------------------------
  // Helpers
  // ----------------------------------------------------------------

  String? _currentBookId() {
    return _dependencies.tabsBloc.state.currentTab?.title;
  }

  String? _currentWorkspaceId() {
    return _dependencies.workspaceBloc.state.activeWorkspaceId;
  }
}
