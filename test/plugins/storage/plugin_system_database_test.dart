import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';

void main() {
  group('PluginSystemDatabase Migration Tests', () {
    test('migrates from v1 to v2 successfully natively', () {
      final db = sqlite3.openInMemory();
      
      // Simulate v1 schema
      db.execute('''
        CREATE TABLE IF NOT EXISTS plugin_installation (
          plugin_id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          version TEXT NOT NULL,
          install_path TEXT NOT NULL,
          entrypoint_path TEXT NOT NULL,
          icon_path TEXT,
          enabled INTEGER NOT NULL,
          pinned INTEGER NOT NULL DEFAULT 1,
          manifest_json TEXT NOT NULL,
          installed_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');

      db.execute('''
        INSERT INTO plugin_installation 
        (plugin_id, name, version, install_path, entrypoint_path, enabled, pinned, manifest_json, installed_at, updated_at) 
        VALUES 
        ('test1', 'Test 1', '1.0.0', '/path1', 'index.html', 1, 1, '{}', '2023-01-01', '2023-01-01')
      ''');

      // Set database version to 1 to simulate a pre-existing app
      db.execute('PRAGMA user_version = 1');

      // V1 check - there is no source_type
      var result = db.select("SELECT * FROM plugin_installation WHERE plugin_id = 'test1'");
      expect(result.first.keys.contains('source_type'), false);

      // Perform Migration to V2 via actual database instance code
      PluginSystemDatabase.instance.migrateSchemaForTest(db);

      // V2 Check - schema updated and default applied
      result = db.select("SELECT * FROM plugin_installation WHERE plugin_id = 'test1'");
      expect(result.first.keys.contains('source_type'), true);
      expect(result.first['source_type'], 'packaged');
      expect(result.first['dev_root_path'], isNull);

      // Add a dev plugin manually to ensure structure supports it
      db.execute('''
        INSERT INTO plugin_installation 
        (plugin_id, name, version, install_path, entrypoint_path, enabled, pinned, manifest_json, installed_at, updated_at, source_type, dev_root_path) 
        VALUES 
        ('test2', 'Test 2', '2.0.0', '/path2', 'dev.html', 1, 1, '{}', '2023-01-01', '2023-01-01', 'development', '/my/dev/path')
      ''');

      result = db.select("SELECT * FROM plugin_installation WHERE plugin_id = 'test2'");
      expect(result.first['source_type'], 'development');
      expect(result.first['dev_root_path'], '/my/dev/path');

      db.close();
    });
  });
}
