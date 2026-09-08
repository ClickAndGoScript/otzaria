import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/text_book_repository.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../test_helpers/memory_cache_provider.dart';

const _commentator = 'רש"י על ספר בדיקה';

/// טעינת הקישורים נכשלת [failuresLeft] פעמים ואחר כך מחזירה קישור לכל שורה.
class _Repository extends TextBookRepository {
  _Repository({required this.failuresLeft})
    : super(fileSystem: FileSystemData.instance);

  int failuresLeft;
  int linkCalls = 0;

  @override
  Future<String> getBookContent(TextBook book) async =>
      List.generate(40, (i) => 'שורה $i').join('\n');

  @override
  Future<BookContentRange?> getBookContentRange(
    TextBook book, {
    required int startLine,
    required int endLine,
  }) async {
    final lines = List.generate(40, (i) => 'שורה $i');
    final start = startLine.clamp(0, lines.length - 1);
    final end = endLine.clamp(start, lines.length - 1);
    return BookContentRange(
      startLine: start,
      endLine: end,
      totalLines: lines.length,
      lines: lines.sublist(start, end + 1),
    );
  }

  @override
  Future<List<TocEntry>> getTableOfContents(TextBook book) async => const [];

  @override
  Future<({List<String> all, Set<String> rare})> getCommentatorsWithRarity(
    TextBook book,
  ) async => (all: const [_commentator], rare: const <String>{});

  @override
  Future<List<Link>> getBookLinksInRange(
    TextBook book, {
    required int startIndex,
    required int endIndex,
    Iterable<String>? targetBookTitles,
  }) async {
    linkCalls++;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    if (failuresLeft > 0) {
      failuresLeft--;
      throw StateError('seforim.db אינו פתוח');
    }
    return [
      for (var line = startIndex; line <= endIndex; line++)
        Link(
          heRef: '$_commentator $line',
          index1: line + 1,
          path2: 'מפרשים/$_commentator',
          index2: line + 1,
          connectionType: 'commentary',
        ),
    ];
  }
}

Future<TextBookLoaded> _waitFor(
  TextBookBloc bloc,
  bool Function(TextBookLoaded state) predicate, {
  required String reason,
}) async {
  final current = bloc.state;
  if (current is TextBookLoaded && predicate(current)) return current;
  return bloc.stream
      .where((s) => s is TextBookLoaded && predicate(s))
      .cast<TextBookLoaded>()
      .first
      .timeout(const Duration(seconds: 10), onTimeout: () => fail(reason));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  test(
    'כשל חולף בטעינת הקישורים אינו נשמר כחלון ריק — הלחיצה הבאה טוענת מחדש '
    '(issue #1216)',
    () async {
      final repository = _Repository(failuresLeft: 1);
      final book = TextBook(title: 'ספר בדיקה', isUserBook: true);
      final bloc = TextBookBloc(
        repository: repository,
        initialState: TextBookInitial.named(book, 10, false, const []),
        scrollController: ItemScrollController(),
        positionsListener: ItemPositionsListener.create(),
      );
      addTearDown(bloc.close);

      bloc.add(
        const LoadContent(
          fontSize: 20,
          showSplitView: false,
          removeNikud: false,
          loadCommentators: true,
        ),
      );
      await _waitFor(
        bloc,
        (s) => s.activeCommentators.isNotEmpty,
        reason: 'המפרשים לא נבחרו',
      );

      // הטעינה הראשונה נכשלת: מצב "טוען" חייב להתאפס ולא להיתקע.
      bloc.add(const UpdateVisibleIndecies([5, 6, 7]));
      await _waitFor(
        bloc,
        (s) => repository.failuresLeft == 0 && !s.linksLoading,
        reason: 'מצב הטעינה לא התאפס אחרי הכשל',
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(bloc.state, isA<TextBookLoaded>());
      expect((bloc.state as TextBookLoaded).linksByLine[6], isNull);

      // לחיצה על קטע באותו חלון — לפני התיקון החלון נחשב "מכוסה" ולא נטען שוב.
      final callsBeforeClick = repository.linkCalls;
      bloc.add(const UpdateSelectedIndex(6));
      final recovered = await _waitFor(
        bloc,
        (s) => s.linksByLine[7]?.isNotEmpty == true,
        reason: 'הקישורים לא נטענו מחדש אחרי הכשל',
      );
      expect(repository.linkCalls, greaterThan(callsBeforeClick));
      expect(recovered.linksLoading, isFalse);
    },
  );
}
