import 'package:equatable/equatable.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';

sealed class PluginSystemState extends Equatable {
  const PluginSystemState();

  @override
  List<Object?> get props => [];
}

class PluginSystemInitial extends PluginSystemState {}

class PluginSystemLoading extends PluginSystemState {}

class PluginSystemLoaded extends PluginSystemState {
  final List<InstalledPlugin> plugins;

  const PluginSystemLoaded(this.plugins);

  @override
  List<Object?> get props => [plugins];
  
  List<InstalledPlugin> get pinnedPlugins => plugins.where((p) => p.pinned).toList();
}

class PluginSystemError extends PluginSystemState {
  final String message;

  const PluginSystemError(this.message);

  @override
  List<Object?> get props => [message];
}

class PluginSystemOverwriteRequired extends PluginSystemState {
  final String archivePath;
  final String pluginName;
  final String version;

  const PluginSystemOverwriteRequired({
    required this.archivePath,
    required this.pluginName,
    required this.version,
  });

  @override
  List<Object?> get props => [archivePath, pluginName, version];
}
