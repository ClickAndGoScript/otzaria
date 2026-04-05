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

class ConfirmPluginInstall extends PluginSystemEvent {
  final String tempDirPath;
  final dynamic manifest; // Passed as dynamic here or use PluginManifest
  const ConfirmPluginInstall(this.tempDirPath, this.manifest);

  @override
  List<Object?> get props => [tempDirPath, manifest];
}

class CancelPluginInstall extends PluginSystemEvent {
  final String tempDirPath;
  const CancelPluginInstall(this.tempDirPath);

  @override
  List<Object?> get props => [tempDirPath];
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

class SetPluginPermissionRequested extends PluginSystemEvent {
  final String pluginId;
  final String permission;
  final bool granted;

  const SetPluginPermissionRequested({
    required this.pluginId,
    required this.permission,
    required this.granted,
  });

  @override
  List<Object?> get props => [pluginId, permission, granted];
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
