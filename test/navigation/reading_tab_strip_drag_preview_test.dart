import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/tab_drag_preview.dart';
import 'package:otzaria/navigation/view/reading_tab_strip.dart';
import 'package:otzaria/tabs/models/tab.dart';

class _StubTab extends OpenedTab {
  _StubTab(super.title);

  @override
  OpenedTab clone() => this;

  @override
  Map<String, dynamic> toJson() => {'type': '_StubTab', 'title': title};
}

void main() {
  const tabWidth = 100.0;

  /// רצועה מעל אזור תוכן אמיתי, כך שיש מה לצלם ל[windowContentBoundaryKey].
  Widget host({
    required List<OpenedTab> tabs,
    required int activeTabIndex,
    required void Function(OpenedTab tab) onSnapshot,
  }) {
    return MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Column(
            children: [
              SizedBox(
                height: 40,
                width: tabs.length * tabWidth,
                child: ReadingTabStrip(
                  stripColor: const Color(0xFFF2EBE0),
                  tabs: tabs,
                  activeTabIndex: activeTabIndex,
                  widths: [for (final _ in tabs) tabWidth],
                  onReorder: (_, _) {},
                  onTabSnapshot: (tab, preview) {
                    preview.image.dispose();
                    onSnapshot(tab);
                  },
                  tabBuilder: (tab, index, width) => SizedBox(
                    width: width,
                    child: ColoredBox(
                      color: const Color(0xFFDDDDDD),
                      child: Center(child: Text(tab.title)),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: RepaintBoundary(
                  key: windowContentBoundaryKey,
                  child: const ColoredBox(
                    color: Color(0xFFFFFFFF),
                    child: Center(child: Text('תוכן הכרטיסיה הפעילה')),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// גוררת כרטיסיה הצדה ומשחררת. `runAsync` נדרש כי הצילום עובר במנוע.
  Future<void> dragAside(WidgetTester tester, String from) async {
    final start = tester.getCenter(find.text(from));
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveTo(start + const Offset(tabWidth * 1.5, 0));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  group('מוק הגרירה מציג רק את תוכן הכרטיסיה הפעילה', () {
    // אזור התוכן מצייר את הכרטיסיה הפעילה בלבד, וגרירה אינה בוחרת כרטיסיה.
    // בלי הגידור, גרירת כרטיסיה אחרת צירפה למוק את תוכן הפעילה.
    testWidgets('גרירת כרטיסיה שאינה פעילה אינה מייצרת מוק עם תוכן', (
      tester,
    ) async {
      final snapshots = <OpenedTab>[];
      final tabs = [_StubTab('א'), _StubTab('ב'), _StubTab('ג')];
      await tester.pumpWidget(
        host(tabs: tabs, activeTabIndex: 1, onSnapshot: snapshots.add),
      );

      await dragAside(tester, 'א');

      expect(snapshots, isEmpty);
    });

    testWidgets('גרירת הכרטיסיה הפעילה כן מייצרת מוק', (tester) async {
      final snapshots = <OpenedTab>[];
      final tabs = [_StubTab('א'), _StubTab('ב'), _StubTab('ג')];
      await tester.pumpWidget(
        host(tabs: tabs, activeTabIndex: 0, onSnapshot: snapshots.add),
      );

      await dragAside(tester, 'א');

      expect(snapshots, [same(tabs[0])]);
    });
  });
}
