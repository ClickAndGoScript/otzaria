// לוגיקה טהורה לבניית קישורי deep link לספרים.
// קובץ זה אינו תלוי ב-Flutter ולכן ניתן לבדיקה עם dart test רגיל.

String _bookSourceSuffix(bool isUserBook) => isUserBook ? '?source=user' : '';

String _queryPrefix(bool isUserBook) => isUserBook ? '?source=user&' : '?';

/// בניית קישור ישיר לספר טקסט לפי מזהה ומקור.
String buildBookLink(int bookId, {bool isUserBook = false}) =>
    'otzaria://open/book/$bookId${_bookSourceSuffix(isUserBook)}';

/// בניית קישור ישיר לספר PDF לפי מזהה ומקור.
String buildPdfBookLink(int bookId, {bool isUserBook = false}) =>
    'otzaria://open/pdf/$bookId${_bookSourceSuffix(isUserBook)}';

/// בניית קישור ישיר למקטע ספציפי בספר טקסט.
/// ערכי index שליליים מוחלפים ב-0.
String buildSectionLink(int bookId, int index, {bool isUserBook = false}) =>
    'otzaria://open/book/$bookId${_queryPrefix(isUserBook)}index=${index < 0 ? 0 : index}';

/// בניית קישור ישיר לעמוד ספציפי בספר PDF.
/// ערכי page שליליים מוחלפים ב-1.
String buildPdfPageLink(int bookId, int page, {bool isUserBook = false}) =>
    'otzaria://open/pdf/$bookId${_queryPrefix(isUserBook)}index=${page < 1 ? 1 : page}';

/// בניית קישור למקטע עם הדגשת המקטע כולו.
/// ערכי index שליליים מוחלפים ב-0.
String buildSectionMarkLink(int bookId, int index, {bool isUserBook = false}) =>
    'otzaria://open/book/$bookId${_queryPrefix(isUserBook)}index=${index < 0 ? 0 : index}&mark';

/// בניית קישור למקטע עם הדגשת טקסט ספציפי.
/// text ריק או רווחים בלבד → מחזיר null (לא לבנות קישור).
/// ערכי index שליליים מוחלפים ב-0.
String? buildTextMarkLink(
  int bookId,
  int index,
  String text, {
  bool isUserBook = false,
}) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  final encoded = Uri.encodeComponent(trimmed);
  return 'otzaria://open/book/$bookId${_queryPrefix(isUserBook)}index=${index < 0 ? 0 : index}&m=$encoded';
}

/// בניית רשימת פריטי תת-תפריט "העתק קישור ישיר" עבור תפריט הלחיצה הימנית.
/// הקישור לספר עצמו מוצג בתפריט "אפשרויות נוספות" שבסרגל העליון, ולכן אינו
/// כלול כאן כדי למנוע כפילות.
/// מחזיר 2 פריטים ללא טקסט מסומן, 3 פריטים עם טקסט מסומן לא-ריק.
/// כל פריט מכיל label ו-link (link יכול להיות null אם הבנייה נכשלה).
List<({String label, String? link})> buildDirectLinkSubmenuEntries({
  required int bookId,
  bool isUserBook = false,
  required int index,
  required String? selectedText,
}) {
  final entries = <({String label, String? link})>[
    (
      label: 'העתק קישור למקטע זה',
      link: buildSectionLink(bookId, index, isUserBook: isUserBook),
    ),
    (
      label: 'העתק קישור עם הדגשת המקטע',
      link: buildSectionMarkLink(bookId, index, isUserBook: isUserBook),
    ),
  ];

  if (selectedText != null && selectedText.trim().isNotEmpty) {
    entries.add((
      label: 'העתק קישור עם הדגשת הטקסט',
      link: buildTextMarkLink(
        bookId,
        index,
        selectedText,
        isUserBook: isUserBook,
      ),
    ));
  }

  return entries;
}
