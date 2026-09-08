import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:otzaria/plugins/bridge/plugin_save_target.dart';

void main() {
  group('pluginSaveFileName', () {
    test('מסיר תווים שאינם חוקיים בשם קובץ', () {
      expect(pluginSaveFileName('a/b\\c:d*e?f"g<h>i|j', null), 'abcdefghij');
    });

    test('משלים את הסיומת המבוקשת, ולא כופל אותה', () {
      expect(pluginSaveFileName('דוח', 'pdf'), 'דוח.pdf');
      expect(pluginSaveFileName('דוח.pdf', 'pdf'), 'דוח.pdf');
      expect(pluginSaveFileName('דוח.PDF', 'pdf'), 'דוח.PDF');
    });

    test('שם ריק נופל לברירת מחדל', () {
      expect(pluginSaveFileName('   ', 'pdf'), 'מסמך.pdf');
      expect(pluginSaveFileName(null, null), 'מסמך');
    });
  });

  group('pluginSaveTargetPath', () {
    final folder = p.join(p.separator, 'tmp', 'saves');

    test('מרכיב נתיב בתוך התיקייה שנבחרה', () {
      expect(
        pluginSaveTargetPath(folder: folder, fileName: 'doc.pdf'),
        p.join(folder, 'doc.pdf'),
      );
    });

    test('שם שחורג מהתיקייה נדחה', () {
      for (final name in ['..', '.', p.join('..', 'escape.pdf')]) {
        expect(
          pluginSaveTargetPath(folder: folder, fileName: name),
          isNull,
          reason: 'השם "$name" אינו אמור להיפתר ליעד',
        );
      }
    });

    test('שם שעבר את pluginSaveFileName אינו יכול לחרוג', () {
      // התוסף שולט בשם המוצע — זהו הצירוף שהגנת המסלול נועדה לחסום.
      final malicious = pluginSaveFileName('../../etc/passwd', null);
      final target = pluginSaveTargetPath(
        folder: folder,
        fileName: malicious,
      );
      expect(target, isNotNull);
      expect(p.dirname(target!), folder);
    });
  });

  group('pluginSaveFolderDialogTitle', () {
    test('שם השלב קודם לכותרת שהתוסף שלח', () {
      expect(
        pluginSaveFolderDialogTitle('שמירת המסמך'),
        'בחירת תיקייה — שמירת המסמך',
      );
      // רווחים בקצה הכותרת אינם נראים בדיאלוג, אבל כן נראים כאן.
      expect(
        pluginSaveFolderDialogTitle('  ייצוא ל-PDF  '),
        'בחירת תיקייה — ייצוא ל-PDF',
      );
    });

    test('כותרת ריקה נופלת לכותרת הקבועה של השלב', () {
      for (final value in [null, '', '   ']) {
        expect(
          pluginSaveFolderDialogTitle(value),
          'בחירת תיקייה לשמירת הקובץ',
          reason: 'הכותרת "$value" אינה אמורה להגיע לדיאלוג',
        );
      }
    });

    test('כל כותרת פותחת ב„בחירת תיקייה”', () {
      // זו הרגרסיה עצמה: כותרת שאינה אומרת „תיקייה” הובילה משתמשים להקליד
      // שם קובץ בבורר התיקיות, ומשם ל-„Path does not exist” של Windows.
      for (final title in [null, 'שמירת המסמך', 'ייצוא לספר אוצריא']) {
        expect(
          pluginSaveFolderDialogTitle(title),
          startsWith('בחירת תיקייה'),
          reason: 'הכותרת "$title" אינה מסמנת שהחלון מבקש תיקייה',
        );
      }
    });
  });
}
