import 'package:equatable/equatable.dart';

sealed class PluginSystemEvent extends Equatable {
  const PluginSystemEvent();

  @override
  List<Object?> get props => [];
}

class LoadPlugins extends PluginSystemEvent {}

class InstallPluginRequested extends PluginSystemEvent {
  final String archivePath;
  final bool forceOverwrite;
  const InstallPluginRequested(this.archivePath, {this.forceOverwrite = false});

  @override
  List<Object?> get props => [archivePath, forceOverwrite];
}

class UninstallPluginRequested extends PluginSystemEvent {
  final String pluginId;
  const UninstallPluginRequested(this.pluginId);

  @override
  List<Object?> get props => [pluginId];
}

class EnablePluginRequested extends PluginSystemEvent {
  final String pluginId;
  const EnablePluginRequested(this.pluginId);

  @override
  List<Object?> get props => [pluginId];
}

class DisablePluginRequested extends PluginSystemEvent {
  final String pluginId;
  const DisablePluginRequested(this.pluginId);

  @override
  List<Object?> get props => [pluginId];
}

class PinPluginRequested extends PluginSystemEvent {
  final String pluginId;
  const PinPluginRequested(this.pluginId);

  @override
  List<Object?> get props => [pluginId];
}

class UnpinPluginRequested extends PluginSystemEvent {
  final String pluginId;
  const UnpinPluginRequested(this.pluginId);

  @override
  List<Object?> get props => [pluginId];
}

class RefreshPlugins extends PluginSystemEvent {}
