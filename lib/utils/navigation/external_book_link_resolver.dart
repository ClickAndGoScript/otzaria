import 'package:otzaria/models/books.dart';

/// מאתר את ספר היעד של קישור עומק. מזהה מסד חופף בין ספר רשמי לאישי
/// ובין טקסט ל-PDF, ולכן ההתאמה דורשת גם מקור וגם סוג.
Book? resolveExternalBookLink(
  Iterable<Book> books,
  int bookId, {
  required bool isUserBook,
  required bool isPdf,
}) {
  for (final book in books) {
    if (book.id == bookId &&
        book.isUserBook == isUserBook &&
        (isPdf
            ? book is PdfBook
            : book is TextBook || book is ConvertibleDocumentBook)) {
      return book;
    }
  }
  return null;
}
