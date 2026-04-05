import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:otzaria/plugins/models/plugin_manifest.dart';

class PluginManifestValidator {
  static Future<void> validateManifest({
    required PluginManifest manifest,
    required String directoryPath,
    String? currentAppVersion,
    bool skipAppVersionValidation = false,
  }) async {
    if (manifest.schemaVersion != 1) {
      throw Exception('גרסת סכמה ${manifest.schemaVersion} של התוסף אינה נתמכת');
    }

    if (!RegExp(r'^[a-z0-9_.-]+$').hasMatch(manifest.id)) {
      throw Exception('מזהה התוסף אינו תקין');
    }

    if (!RegExp(r'^\d+\.\d+\.\d+(?:\+.*)?$').hasMatch(manifest.version)) {
      throw Exception('גרסת התוסף במניפסט אינה חוקית. נדרש פורמט SemVer חוקיות.');
    }



    int compareVersionsStrict(String v1, String v2) {
      final parts1 = v1.split('+')[0].split('.').map(int.parse).toList();
      final parts2 = v2.split('+')[0].split('.').map(int.parse).toList();
      for (var i = 0; i < 3; i++) {
        final p1 = i < parts1.length ? parts1[i] : 0;
        final p2 = i < parts2.length ? parts2[i] : 0;
        if (p1 > p2) return 1;
        if (p1 < p2) return -1;
      }
      return 0;
    }

    if (!skipAppVersionValidation) {
      if (currentAppVersion == null) {
        throw Exception('currentAppVersion is required when skipAppVersionValidation is false');
      }
      if (compareVersionsStrict(currentAppVersion, manifest.minAppVersion) < 0) {
        throw Exception('התוסף דורש אוצריא בגרסה ${manifest.minAppVersion} לפחות, אך מותקנת $currentAppVersion');
      }
      if (manifest.maxAppVersion != null &&
          compareVersionsStrict(currentAppVersion, manifest.maxAppVersion!) > 0) {
        throw Exception('התוסף מיועד לאוצריא עד גרסה ${manifest.maxAppVersion} בלבד, אך מותקנת $currentAppVersion');
      }
    }

    const validPermissions = [
      'app.info.read',
      'library.books.read',
      'library.content.read',
      'search.fulltext.read',
      'reader.open',
      'navigation.write',
      'notes.read',
      'notes.write',
      'calendar.read',
      'settings.read',
      'ui.feedback',
      'plugin.storage.read',
      'plugin.storage.write',
      'published_data.write',
      'network.access',
      'events.subscribe:navigation.changed',
      'events.subscribe:reader.current_book_changed',
      'events.subscribe:theme.changed',
      'events.subscribe:settings.changed',
      'events.subscribe:calendar.date_changed',
      'events.subscribe:workspace.changed',
      'events.subscribe:plugin.permissions_changed'
    ];
    for (final perm in manifest.permissions) {
      if (!validPermissions.contains(perm)) {
        throw Exception('הרשאה לא חוקית שנדרשת על ידי התוסף: $perm');
      }
    }

    final entrypointPath = p.normalize(p.join(directoryPath, manifest.entrypoint));
    if (!p.isWithin(directoryPath, entrypointPath)) {
      throw Exception('נתיב קובץ הכניסה ${manifest.entrypoint} חורג מגבולות תיקיית התוסף');
    }
    if (!File(entrypointPath).existsSync()) {
      throw Exception('קובץ הכניסה ${manifest.entrypoint} לא נמצא בתיקייה');
    }
  }
}
