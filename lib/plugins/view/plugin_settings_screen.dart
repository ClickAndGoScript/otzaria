import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/widgets/custom_ui_components.dart';
import 'package:otzaria/settings/settings_card.dart';

class PluginSettingsScreen extends StatefulWidget {
  final InstalledPlugin plugin;
  
  const PluginSettingsScreen({super.key, required this.plugin});
  
  @override
  State<PluginSettingsScreen> createState() => _PluginSettingsScreenState();
}

class _PluginSettingsScreenState extends State<PluginSettingsScreen> {
  final _repo = PluginRegistryRepository();
  Map<String, bool> _permissions = {};

  @override
  void initState() {
    super.initState();
    _loadPermissions();
  }

  Future<void> _loadPermissions() async {
    Map<String, bool> map = {};
    for (final p in widget.plugin.manifest.permissions) {
      final granted = await _repo.getPermission(widget.plugin.pluginId, p);
      map[p] = granted ?? true; // True is default per the bridge logic
    }
    setState(() {
      _permissions = map;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Wrap with BlocBuilder so that we get latest state (e.g. for enabled)
    return BlocBuilder<PluginSystemBloc, PluginSystemState>(
      builder: (context, state) {
        InstalledPlugin currentPlugin = widget.plugin;
        if (state is PluginSystemLoaded) {
          try {
             currentPlugin = state.plugins.firstWhere((p) => p.pluginId == widget.plugin.pluginId);
          } catch (_) {
             // plugin uninstalled or not found
          }
        }

        return Scaffold(
          appBar: AppBar(title: Text('הגדרות תוסף: ${currentPlugin.name}')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SettingsCard(
                title: 'הגדרות כלליות',
                children: [
                  SwitchListTile(
                    title: const Text('מצב מופעל (Enabled)'),
                    subtitle: const Text('כיבוי ימנע מהתוסף לרוץ לחלוטין באפליקציה'),
                    value: currentPlugin.enabled,
                    onChanged: (val) {
                      if (val) {
                        context.read<PluginSystemBloc>().add(EnablePluginRequested(currentPlugin.pluginId));
                      } else {
                        context.read<PluginSystemBloc>().add(DisablePluginRequested(currentPlugin.pluginId));
                      }
                    },
                    hoverColor: Colors.transparent,
                  ),
                ],
              ),
              if (currentPlugin.manifest.permissions.isNotEmpty) ...[
                const SizedBox(height: 16),
                SettingsCard(
                  title: 'ניהול הרשאות',
                  subtitle: 'אפשר או חסום הרשאות ספציפיות כפי שנדרש במניפסט',
                  children: currentPlugin.manifest.permissions.map((p) {
                    return SwitchListTile(
                      title: Text(p),
                      value: _permissions[p] ?? true,
                      onChanged: (val) async {
                        context.read<PluginSystemBloc>().add(
                           SetPluginPermissionRequested(
                             pluginId: currentPlugin.pluginId, 
                             permission: p, 
                             granted: val
                           )
                        );
                        setState(() {
                          _permissions[p] = val;
                        });
                      },
                      hoverColor: Colors.transparent,
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 32),
              NeutralActionButton(
                text: 'הסרת תוסף',
                onPressed: () async {
                  final confirm = await showWarningDialog(
                     context: context,
                     title: 'מחיקת תוסף סופית',
                     content: 'האם אתה בטוח שברצונך למחוק את התוסף "${currentPlugin.name}"?',
                     subtitle: 'המחיקה תכלול את כל נתוני התוסף, המטמון והפעולות שלו. הליך זה סופי.',
                     cancelText: 'ביטול',
                     confirmText: 'מחק',
                  );
                  if (confirm == true && context.mounted) {
                     context.read<PluginSystemBloc>().add(UninstallPluginRequested(currentPlugin.pluginId));
                     Navigator.of(context).pop();
                  }
                },
              )
            ],
          ),
        );
      }
    );
  }
}
