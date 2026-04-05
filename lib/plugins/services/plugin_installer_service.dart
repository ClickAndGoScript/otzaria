import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:archive/archive_io.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';

class PluginOverwriteException implements Exception {
  final String pluginName;
  final String version;
  PluginOverwriteException(this.pluginName, this.version);
}

class PreparedInstall {
  final PluginManifest manifest;
  final String tempDirPath;
  final bool isOverwrite;
  
  PreparedInstall(this.manifest, this.tempDirPath, this.isOverwrite);
}

class PluginInstallerService {
  final PluginRegistryRepository _repository = PluginRegistryRepository();

  Future<PreparedInstall> prepareInstall(String archivePath, {bool forceOverwrite = false}) async {
    final tempDir = await Directory.systemTemp.createTemp('otz_plugin_');
    try {
      // 1. Extract zip to temp
      final bytes = File(archivePath).readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(bytes);

      for (final file in archive) {
        final filename = file.name;
        final targetPath = p.normalize(p.join(tempDir.path, filename));
        if (!p.isWithin(tempDir.path, targetPath)) {
          throw Exception('נתיב חולץ מקובץ ZIP באופן לא חוקי: $filename');
        }

        if (file.isFile) {
          final data = file.content as List<int>;
          File(targetPath)
            ..createSync(recursive: true)
            ..writeAsBytesSync(data);
        } else {
          Directory(targetPath).createSync(recursive: true);
        }
      }

      // 2. Read manifest
      final manifestFile = File(p.join(tempDir.path, 'manifest.json'));
      if (!manifestFile.existsSync()) {
        throw Exception('manifest.json לא נמצא בחבילת התוסף');
      }

      final manifestJson = jsonDecode(await manifestFile.readAsString());
      final manifest = PluginManifest.fromJson(manifestJson);

      if (manifest.schemaVersion != 1) {
         throw Exception('גרסת סכמה ${manifest.schemaVersion} של התוסף אינה נתמכת במערכת זו');
      }

      if (!RegExp(r'^[a-z0-9_.-]+$').hasMatch(manifest.id)) {
        throw Exception('מזהה התוסף אינו תקין. מותר להשתמש רק באותיות קטנות באנגלית, מספרים, נקודות, קווים תחתונים ומינוסים.');
      }
      
      if (!RegExp(r'^\d+\.\d+\.\d+(?:\+.*)?$').hasMatch(manifest.version)) {
         throw Exception('גרסת התוסף במניפסט אינה חוקית. נדרש פורמט SemVer חוקיות (לדוגמה 1.0.0).');
      }

      bool isOverwrite = false;
      final existingPlugin = await _repository.getPlugin(manifest.id);
      if (existingPlugin != null) {
         final diff = _compareVersionsStrict(manifest.version, existingPlugin.version);
         if (diff < 0) {
           throw Exception('לא ניתן להתקין גרסה ${manifest.version} על פני גרסה חדישה יותר ${existingPlugin.version}. מחיקה נדרשת קודם.');
         } else if (diff == 0 && !forceOverwrite) {
           throw PluginOverwriteException(manifest.name, manifest.version);
         }
         isOverwrite = true;
      }

      final packageInfo = await PackageInfo.fromPlatform();
      final appVersion = packageInfo.version;
      if (_compareVersionsStrict(appVersion, manifest.minAppVersion) < 0) {
        throw Exception('התוסף דורש אוצריא בגרסה ${manifest.minAppVersion} לפחות, אך מותקנת $appVersion');
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

      if (!File(p.join(tempDir.path, manifest.entrypoint)).existsSync()) {
        throw Exception('קובץ הכניסה ${manifest.entrypoint} לא נמצא בחבילה');
      }

      return PreparedInstall(manifest, tempDir.path, isOverwrite);

    } catch (e) {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
      rethrow;
    }
  }

  Future<void> finalizeInstall(String tempDirPath, PluginManifest manifest) async {
    final tempDir = Directory(tempDirPath);
    try {
      final existingPlugin = await _repository.getPlugin(manifest.id);

      // 3. Move to install path
      final installPath = await AppPaths.getPluginInstallPath(manifest.id);
      final installDir = Directory(installPath);
      if (await installDir.exists()) {
        await installDir.delete(recursive: true);
      }
      await installDir.create(recursive: true);

      // We move files by copying
      await _copyDirectory(tempDir, installDir);

      // 4. Save to DB
      final plugin = InstalledPlugin(
        pluginId: manifest.id,
        name: manifest.name,
        version: manifest.version,
        installPath: installPath,
        entrypointPath: manifest.entrypoint,
        iconPath: manifest.icon,
        enabled: existingPlugin?.enabled ?? true,
        pinned: existingPlugin?.pinned ?? manifest.defaultPinned,
        manifest: manifest,
        installedAt: existingPlugin?.installedAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await _repository.savePlugin(plugin);

      // User confirmed UI prompt, so seed grants for requested permissions safely.
      for (final perm in manifest.permissions) {
         await _repository.setPermission(manifest.id, perm, true);
      }

    } finally {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  Future<void> cancelInstall(String tempDirPath) async {
    final tempDir = Directory(tempDirPath);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await for (var entity in source.list(recursive: false)) {
      if (entity is Directory) {
        var newDirectory = Directory(p.join(destination.path, p.basename(entity.path)));
        await newDirectory.create(recursive: true);
        await _copyDirectory(entity.absolute, newDirectory);
      } else if (entity is File) {
        await entity.copy(p.join(destination.path, p.basename(entity.path)));
      }
    }
  }

  Future<void> uninstallPlugin(String pluginId) async {
    final plugin = await _repository.getPlugin(pluginId);
    if (plugin != null) {
      await _repository.deletePlugin(pluginId);
      final installDir = Directory(plugin.installPath);
      if (installDir.existsSync()) {
        installDir.deleteSync(recursive: true);
      }
      final dataPath = await AppPaths.getPluginDataPath(pluginId);
      final cachePath = await AppPaths.getPluginCachePath(pluginId);
      final dataDir = Directory(dataPath);
      if (dataDir.existsSync()) dataDir.deleteSync(recursive: true);
      final cacheDir = Directory(cachePath);
      if (cacheDir.existsSync()) cacheDir.deleteSync(recursive: true);
    }
  }

  int _compareVersionsStrict(String v1, String v2) {
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
}
