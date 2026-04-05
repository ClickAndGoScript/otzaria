import 'package:collection/collection.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_debug_logger.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';

class BookOpenCoordinator {
  final TabsBloc tabsBloc;
  final HistoryBloc historyBloc;
  final NavigationBloc navigationBloc;

  const BookOpenCoordinator({
    required this.tabsBloc,
    required this.historyBloc,
    required this.navigationBloc,
  });

  void openBook(
    Book book,
    int index,
    String searchQuery, {
    bool ignoreHistory = false,
  }) {
    final scope = PageShapeDebugLogger.newScope(
      'open-book',
      label: book.title,
    );
    final trace = PageShapeDebugLogger.start(
      'OpenBook',
      'פתיחת ספר',
      scope: scope,
      data: {
        'bookTitle': book.title,
        'index': index,
        'searchQueryLength': searchQuery.length,
        'ignoreHistory': ignoreHistory,
        'bookType': book.runtimeType,
      },
    );

    try {
      final tabsState = tabsBloc.state;
      trace.step(
        'מצב טאבים לפני פתיחה',
        data: {
          'hasOpenTabs': tabsState.hasOpenTabs,
          'currentTabTitle': tabsState.currentTab?.title,
          'tabsCount': tabsState.tabs.length,
        },
      );
      if (tabsState.hasOpenTabs) {
        historyBloc.add(CaptureStateForHistory(tabsState.currentTab!));
        trace.step(
          'נשלחה בקשה לשמירת מצב נוכחי להיסטוריה',
          data: {
            'capturedTabTitle': tabsState.currentTab?.title,
          },
        );
      }

      final historyState = historyBloc.state;
      final lastOpened = ignoreHistory
          ? null
          : historyState.history
              .firstWhereOrNull((b) => b.book.title == book.title);
      trace.step(
        'נבדקה היסטוריה לספר',
        data: {
          'historyLength': historyState.history.length,
          'lastOpenedIndex': lastOpened?.index,
          'lastOpenedCommentatorsCount': lastOpened?.commentatorsToShow.length,
        },
      );

      final initialIndex =
          (ignoreHistory || index != 0) ? index : (lastOpened?.index ?? 0);
      final initialCommentators = lastOpened?.commentatorsToShow;

      final shouldOpenLeftPane =
          (Settings.getValue<bool>('key-pin-sidebar') ?? false) ||
              (Settings.getValue<bool>('key-default-sidebar-open') ?? false);

      final savedViewMode =
          PageShapeSettingsManager.getViewModePreference(book.title);
      trace.step(
        'חושבו פרמטרי הפתיחה',
        data: {
          'initialIndex': initialIndex,
          'initialCommentatorsCount': initialCommentators?.length,
          'shouldOpenLeftPane': shouldOpenLeftPane,
          'savedPageShapeViewMode': savedViewMode,
        },
      );

      final tab = OpenedTab.fromBook(
        book,
        initialIndex,
        searchText: searchQuery,
        commentators: initialCommentators,
        openLeftPane: shouldOpenLeftPane,
        showPageShapeView: savedViewMode,
      );
      trace.step(
        'נוצר טאב לפתיחה',
        data: {
          'tabType': tab.runtimeType,
          'tabTitle': tab.title,
        },
      );
      tabsBloc.add(OpenOrFocusTab(tab));
      trace.step('נשלח אירוע OpenOrFocusTab');

      navigationBloc.add(const NavigateToScreen(Screen.reading));
      trace.end(
        data: {
          'navigationTarget': Screen.reading.name,
        },
      );
    } catch (error, stackTrace) {
      trace.fail(error, stackTrace);
      rethrow;
    }
  }
}
