import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/settings/settings_exports.dart';

enum InstallMode { systemWide, perUser }

/// Utility class for managing application paths.
/// Centralizes path construction logic to avoid duplication.
class AppPaths {
  /// Detects whether the app is installed system-wide or per-user.
  static Future<InstallMode> detectInstallMode() async {
    if (Platform.isMacOS) {
      if (await Directory('/Library/Application Support/Otzaria').exists()) {
        return InstallMode.systemWide;
      }
    }
    if (Platform.isWindows) {
      final exeDir = p.dirname(Platform.resolvedExecutable);
      if (File(p.join(exeDir, 'system_install.marker')).existsSync()) {
        return InstallMode.systemWide;
      }
    }
    if (Platform.isLinux) {
      if (await Directory('/var/lib/otzaria').exists()) {
        return InstallMode.systemWide;
      }
    }
    return InstallMode.perUser;
  }

  /// Default library path based on install mode and platform.
  static Future<String> getDefaultLibraryPath() async {
    final mode = await detectInstallMode();
    if (mode == InstallMode.systemWide) {
      if (Platform.isWindows) {
        final pd = Platform.environment['ProgramData'] ?? r'C:\ProgramData';
        return p.join(pd, 'otzaria', 'books');
      }
      if (Platform.isMacOS) return '/Library/Application Support/otzaria/books';
      if (Platform.isLinux) return '/var/lib/otzaria/books';
    }

    // Per-user defaults
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'] ?? '';
      return p.join(appData, 'otzaria', 'books');
    }
    if (Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? '';
      return p.join(home, 'Library', 'Application Support', 'otzaria', 'books');
    }
    if (Platform.isLinux) {
      final home = Platform.environment['HOME'] ?? '';
      return p.join(home, '.local', 'share', 'otzaria', 'books');
    }
    if (Platform.isAndroid) {
      try {
        final ext = await getExternalStorageDirectory();
        return p.join(
            ext?.path ?? (await getApplicationDocumentsDirectory()).path,
            'otzaria',
            'books');
      } catch (_) {
        return p.join((await getApplicationDocumentsDirectory()).path,
            'otzaria', 'books');
      }
    }
    if (Platform.isIOS) {
      return p.join(
          (await getApplicationDocumentsDirectory()).path, 'otzaria', 'books');
    }
    return p.join(
        (await getApplicationDocumentsDirectory()).path, 'otzaria', 'books');
  }

  /// Gets the main library path from settings, or gracefully falls back to default paths.
  static Future<String> getLibraryPath() async {
    // Check existing library path setting
    final currentPath =
        Settings.getValue<String>(SettingsRepository.keyLibraryPath);

    if (currentPath != null && currentPath.isNotEmpty) {
      return currentPath;
    }

    // Determine default path based on platform
    String libraryPath = await getDefaultLibraryPath();

    await Settings.setValue(SettingsRepository.keyLibraryPath, libraryPath);
    return libraryPath;
  }

  /// Gets the search index path (library_path/index)
  static Future<String> getIndexPath() async {
    // Check if there is a separate index path assigned
    final savedIndex =
        Settings.getValue<String>(SettingsRepository.keyIndexPath);
    if (savedIndex != null && savedIndex.isNotEmpty) return savedIndex;

    // fallback: parallel to the library path (otzaria/index)
    final libraryPath = await getLibraryPath();
    final parentDir = p.dirname(libraryPath);
    return p.join(parentDir, 'index');
  }

  /// Returns user's generic backup path.
  static Future<String> getDefaultBackupPath() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final docs = await getApplicationDocumentsDirectory();
      return p.join(docs.path, 'OtzariaBackups');
    } else {
      // Mobile
      final docs = await getApplicationDocumentsDirectory();
      return p.join(docs.path, 'backups');
    }
  }

  /// Gets backup path from settings.
  static Future<String> getBackupPath() async {
    final saved = Settings.getValue<String>(SettingsRepository.keyBackupPath);
    if (saved != null && saved.isNotEmpty) return saved;
    return getDefaultBackupPath();
  }

  /// Gets the shared directory used for Tantivy lock/state files.
  /// It is kept next to the index directory so all users of the same
  /// installation can access the same lock files.
  static Future<String> getTantivyLockPath() async {
    final indexPath = await getIndexPath();
    final lockDir = Directory(p.join(p.dirname(indexPath), 'tantivy.lock'));
    if (!await lockDir.exists()) {
      await lockDir.create(recursive: true);
    }
    return lockDir.path;
  }

  /// Gets the previous per-user location of the Tantivy lock/state files.
  /// Used only for migration to the shared `tantivy.lock` directory.
  static Future<String> getLegacyIndexStatePath() async {
    final support = await getApplicationSupportDirectory();
    return p.join(support.path, 'index_state');
  }

  /// Gets the manifest file path (library_path/files_manifest.json)
  static Future<String> getManifestPath() async {
    final libraryPath = await getLibraryPath();
    return p.join(libraryPath, 'files_manifest.json');
  }

  /// Resolves the notes database path - for cross-platform compatibility.
  /// Also migrates the DB from the old sqflite location the first time it runs on mobile.
  static Future<String> resolveNotesDbPath(String fileName) async {
    final Directory dbDir;
    if (Platform.isAndroid || Platform.isIOS) {
      final appDir = await getApplicationDocumentsDirectory();
      dbDir = Directory(p.join(appDir.path, 'databases'));
    } else {
      final support = await getApplicationSupportDirectory();
      dbDir = Directory(p.join(support.path, 'databases'));
    }
    if (!await dbDir.exists()) await dbDir.create(recursive: true);
    final newPath = p.join(dbDir.path, fileName);

    // Migrate from old sqflite location on mobile (one-time, idempotent)
    if (!File(newPath).existsSync()) {
      await _migrateNotesDbIfExists(fileName, newPath);
    }

    return newPath;
  }

  /// Copies the old sqflite database file to [newPath] if it exists at the
  /// platform-specific sqflite default location.
  static Future<void> _migrateNotesDbIfExists(
      String fileName, String newPath) async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      // sqflite stored the DB differently per platform:
      //   Android: {app}/databases/ (sibling of the 'files' dir)
      //   iOS:     Library/ (parent of Application Support)
      final oldDir = Platform.isAndroid
          ? p.join(supportDir.parent.path, 'databases')
          : supportDir.parent.path;
      final oldFile = File(p.join(oldDir, fileName));
      if (await oldFile.exists()) {
        await oldFile.copy(newPath);
      }
    } catch (_) {
      // Migration is best-effort; failure should not prevent the app from starting.
    }
  }

  /// Creates necessary directories for the application
  /// Note: Does NOT create the library path itself - only index directories
  /// The library path should be created by the user or during library download
  static Future<void> createNecessaryDirectories() async {
    // Index directory is created by TantivyDataProvider._initEngine().
    // No other directories need pre-creation at startup.
  }

  /// Gets the root path for all plugin data.
  static Future<String> getPluginsRootPath() async {
    final Directory baseDir;
    if (Platform.isAndroid || Platform.isIOS) {
      baseDir = await getApplicationDocumentsDirectory();
    } else {
      baseDir = await getApplicationSupportDirectory();
    }
    return p.join(baseDir.path, 'plugins');
  }

  /// Gets the path where downloaded/extracted plugins are installed.
  static Future<String> getInstalledPluginsPath() async {
    final root = await getPluginsRootPath();
    return p.join(root, 'installed');
  }

  /// Gets the path for a specific plugin installation.
  static Future<String> getPluginInstallPath(String pluginId) async {
    final installed = await getInstalledPluginsPath();
    return p.join(installed, pluginId, 'current');
  }

  /// Gets the generic data path for a specific plugin.
  static Future<String> getPluginDataPath(String pluginId) async {
    final root = await getPluginsRootPath();
    return p.join(root, 'data', pluginId);
  }

  /// Gets the cache path for a specific plugin.
  static Future<String> getPluginCachePath(String pluginId) async {
    final root = await getPluginsRootPath();
    return p.join(root, 'cache', pluginId);
  }

  /// Resolves the plugin system database path.
  static Future<String> resolvePluginsDbPath() async {
    return resolveNotesDbPath('plugins_host.db');
  }
}
