import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';

class PluginRegistryRepository {
  final PluginSystemDatabase _db = PluginSystemDatabase.instance;

  Future<List<InstalledPlugin>> getAllPlugins() async {
    return _db.getAllInstalledPlugins();
  }

  Future<InstalledPlugin?> getPlugin(String pluginId) async {
    return _db.getInstalledPlugin(pluginId);
  }

  Future<void> savePlugin(InstalledPlugin plugin) async {
    await _db.insertOrUpdatePlugin(plugin);
  }

  Future<void> deletePlugin(String pluginId) async {
    await _db.deletePlugin(pluginId);
  }

  Future<void> updatePinState(String pluginId, bool pinned) async {
    await _db.updatePluginPinState(pluginId, pinned);
  }
}
