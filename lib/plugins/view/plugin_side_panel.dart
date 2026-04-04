import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';

class PluginSidePanel extends StatelessWidget {
  final Function(InstalledPlugin)? onPluginSelected;
  const PluginSidePanel({super.key, this.onPluginSelected});

  Future<void> _installPlugin(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['otzplugin'],
    );
    if (result != null && result.files.single.path != null) {
      if (context.mounted) {
        context.read<PluginSystemBloc>().add(InstallPluginRequested(result.files.single.path!));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border(
          left: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1.0,
          ),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'תוספים',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
                IconButton(
                  icon: const Icon(FluentIcons.add_24_regular),
                  tooltip: 'התקן תוסף חדש',
                  onPressed: () => _installPlugin(context),
                )
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: BlocBuilder<PluginSystemBloc, PluginSystemState>(
              builder: (context, state) {
                if (state is PluginSystemLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state is PluginSystemError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text('שגיאה: ${state.message}'),
                    ),
                  );
                }
                if (state is PluginSystemLoaded) {
                  final plugins = state.plugins;
                  if (plugins.isEmpty) {
                    return const Center(
                      child: Text('לא הותקנו תוספים'),
                    );
                  }
                  return ListView.builder(
                    itemCount: plugins.length,
                    itemBuilder: (context, index) {
                      final plugin = plugins[index];
                      return ListTile(
                        leading: const Icon(FluentIcons.puzzle_piece_24_regular),
                        title: Text(plugin.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(plugin.version),
                        trailing: IconButton(
                          icon: Icon(
                            plugin.pinned
                                ? FluentIcons.pin_24_filled
                                : FluentIcons.pin_24_regular,
                          ),
                          onPressed: () {
                            if (plugin.pinned) {
                              context.read<PluginSystemBloc>().add(UnpinPluginRequested(plugin.pluginId));
                            } else {
                              context.read<PluginSystemBloc>().add(PinPluginRequested(plugin.pluginId));
                            }
                          },
                        ),
                        onTap: () {
                          if (onPluginSelected != null) {
                            onPluginSelected!(plugin);
                          }
                        },
                      );
                    },
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ],
      ),
    );
  }
}
