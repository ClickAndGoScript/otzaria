import 'package:path/path.dart' as p;

/// שם קובץ בטוח לדיאלוג „שמור בשם”: מסיר תווים שאינם חוקיים ומשלים סיומת.
///
/// התווים מוסרים כאן ולא נסמכים על הדיאלוג, שמתנהג שונה בכל פלטפורמה.
String pluginSaveFileName(String? requested, String? extension) {
  final cleaned = (requested ?? '')
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
      .trim();
  final base = cleaned.isEmpty ? 'מסמך' : cleaned;
  if (extension == null || extension.isEmpty) return base;
  return base.toLowerCase().endsWith('.$extension') ? base : '$base.$extension';
}

/// מרכיב את נתיב היעד בתוך [folder], או `null` אם [fileName] חורג ממנה.
///
/// התוסף שולט בשם המוצע שממלא את שדה השם, ושם כמו ".." היה מפנה את הכתיבה
/// אל מחוץ לתיקייה שהמשתמש בחר.
String? pluginSaveTargetPath({
  required String folder,
  required String fileName,
}) {
  final root = p.normalize(folder);
  final target = p.normalize(p.join(root, fileName));
  if (p.dirname(target) != root || p.basename(target) != fileName) return null;
  return target;
}

/// כותרת לדיאלוג בחירת התיקייה — השלב הראשון של „שמור בשם” של תוסף.
///
/// „שמור בשם” הוא שני חלונות בזה אחר זה: בורר התיקיות של המערכת, ואחריו
/// דיאלוג שם הקובץ. הכותרת שהתוסף שולח מתארת את הפעולה כולה („שמירת
/// המסמך”), והצבתה כפי שהיא על בורר התיקיות מסתירה שהחלון הזה מבקש
/// **תיקייה**: משתמש שקיבל חלון בשם „שמירת המסמך” הקליד בשדה שלו שם קובץ,
/// ובורר התיקיות של Windows דחה אותו ב„Path does not exist” — תחת אותה
/// כותרת, כך שנראה כאילו השמירה עצמה נכשלה.
///
/// שם השלב קודם לכותרת של התוסף ואינו מחליף אותה: „ייצוא ל-PDF” הוא מה
/// שמבדיל בין שתי שמירות של אותו תוסף, ובלעדיו כל בורר תיקייה נראה זהה.
String pluginSaveFolderDialogTitle(String? pluginTitle) {
  final trimmed = pluginTitle?.trim();
  if (trimmed == null || trimmed.isEmpty) return 'בחירת תיקייה לשמירת הקובץ';
  return 'בחירת תיקייה — $trimmed';
}
