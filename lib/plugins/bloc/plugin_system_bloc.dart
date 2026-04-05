import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_installer_service.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/services/plugin_dev_loader_service.dart';
import 'package:otzaria/plugins/services/plugin_dev_watch_service.dart';
import 'dart:async';
import 'package:otzaria/core/ui_snack.dart';

class PluginSystemBloc extends Bloc<PluginSystemEvent, PluginSystemState> {
  final PluginRegistryRepository repository;
  final PluginInstallerService _installerService;
  final PluginDevLoaderService devLoader;
  final PluginDevWatchService devWatchService;
  StreamSubscription<PluginDevFsChange>? _devWatchSub;

  PluginSystemBloc({
    required this.repository,
    PluginInstallerService? installerService,
    PluginDevLoaderService? devLoader,
    PluginDevWatchService? devWatchService,
  })  : _installerService =
            installerService ?? PluginInstallerService(repository: repository),
        devLoader = devLoader ?? PluginDevLoaderService(repository: repository),
        devWatchService = devWatchService ?? PluginDevWatchService(),
        super(PluginSystemInitial()) {
    on<LoadPlugins>(_onLoadPlugins);
    on<InstallPluginRequested>(_onInstallPluginRequested);
    on<ConfirmPluginInstall>(_onConfirmPluginInstall);
    on<CancelPluginInstall>(_onCancelPluginInstall);
    on<UninstallPluginRequested>(_onUninstallPluginRequested);
    on<PinPluginRequested>(_onPinPluginRequested);
    on<UnpinPluginRequested>(_onUnpinPluginRequested);
    on<EnablePluginRequested>(_onEnablePluginRequested);
    on<DisablePluginRequested>(_onDisablePluginRequested);
    on<SetPluginPermissionRequested>(_onSetPluginPermissionRequested);
    on<RefreshPlugins>((event, emit) => add(LoadPlugins()));
    on<LoadDevelopmentPluginRequested>(_onLoadDevelopmentPluginRequested);
    on<DetachDevelopmentPluginRequested>(_onDetachDevelopmentPluginRequested);
    on<ReloadDevelopmentPluginRequested>(_onReloadDevelopmentPluginRequested);
    on<DevelopmentPluginManifestChanged>(_onDevelopmentPluginManifestChanged);

    _devWatchSub = this.devWatchService.events.listen((change) {
      if (change.manifestChanged) {
        add(DevelopmentPluginManifestChanged(change.pluginId));
      } else {
        PluginRuntimeDispatcher.instance.reloadPlugin(change.pluginId);
      }
    });
  }

  @override
  Future<void> close() {
    _devWatchSub?.cancel();
    devWatchService.dispose();
    return super.close();
  }

  Future<void> _onLoadPlugins(
      LoadPlugins event, Emitter<PluginSystemState> emit) async {
    emit(PluginSystemLoading());
    try {
      final plugins = await repository.getAllPlugins();
      devWatchService.syncWatchers(await repository.getDevelopmentPlugins());
      emit(PluginSystemLoaded(plugins));
    } catch (e) {
      emit(PluginSystemError(e.toString()));
      UiSnack.showError('שגיאה בטעינת תוספים: ${e.toString()}');
    }
  }

  Future<void> _onPinPluginRequested(
      PinPluginRequested event, Emitter<PluginSystemState> emit) async {
    try {
      await repository.updatePinState(event.pluginId, true);
      add(LoadPlugins());
    } catch (e) {
      UiSnack.showError('שגיאה בהצמדת התוסף: ${e.toString()}');
    }
  }

  Future<void> _onUnpinPluginRequested(
      UnpinPluginRequested event, Emitter<PluginSystemState> emit) async {
    try {
      await repository.updatePinState(event.pluginId, false);
      add(LoadPlugins());
    } catch (e) {
      UiSnack.showError('שגיאה בהסרת הצמדת התוסף: ${e.toString()}');
    }
  }

  Future<void> _onInstallPluginRequested(
      InstallPluginRequested event, Emitter<PluginSystemState> emit) async {
    try {
      final prepareInfo = await _installerService.prepareInstall(
          event.archivePath,
          forceOverwrite: event.forceOverwrite);

      emit(PluginSystemInstallRequiresPermissions(
        manifest: prepareInfo.manifest,
        tempDirPath: prepareInfo.tempDirPath,
      ));
    } on PluginOverwriteException catch (e) {
      emit(PluginSystemOverwriteRequired(
        archivePath: event.archivePath,
        pluginName: e.pluginName,
        version: e.version,
      ));
    } catch (e) {
      UiSnack.showError('שגיאה בהתקנת התוסף: ${e.toString()}');
      add(LoadPlugins()); // Reset state
    }
  }

  Future<void> _onConfirmPluginInstall(
      ConfirmPluginInstall event, Emitter<PluginSystemState> emit) async {
    try {
      await _installerService.finalizeInstall(
          event.tempDirPath, event.manifest);
      UiSnack.showSuccess('התוסף הותקן בהצלחה ונוצרו הרשאות');
      add(LoadPlugins());
    } catch (e) {
      await _installerService.cancelInstall(event.tempDirPath);
      UiSnack.showError('שגיאה באישור התקנה: ${e.toString()}');
      add(LoadPlugins());
    }
  }

  Future<void> _onCancelPluginInstall(
      CancelPluginInstall event, Emitter<PluginSystemState> emit) async {
    await _installerService.cancelInstall(event.tempDirPath);
    add(LoadPlugins());
  }

  Future<void> _onUninstallPluginRequested(
      UninstallPluginRequested event, Emitter<PluginSystemState> emit) async {
    try {
      await _installerService.uninstallPlugin(event.pluginId);
      add(LoadPlugins());
    } catch (e) {
      UiSnack.showError('שגיאה בהסרת התוסף: ${e.toString()}');
    }
  }

  Future<void> _onEnablePluginRequested(
      EnablePluginRequested event, Emitter<PluginSystemState> emit) async {
    try {
      final plugin = await repository.getPlugin(event.pluginId);
      if (plugin != null) {
        await repository.savePlugin(plugin.copyWith(enabled: true));
        add(LoadPlugins());
      }
    } catch (e) {
      UiSnack.showError('שגיאה בהפעלת התוסף: ${e.toString()}');
    }
  }

  Future<void> _onDisablePluginRequested(
      DisablePluginRequested event, Emitter<PluginSystemState> emit) async {
    try {
      final plugin = await repository.getPlugin(event.pluginId);
      if (plugin != null) {
        await repository.savePlugin(plugin.copyWith(enabled: false));
        add(LoadPlugins());
      }
    } catch (e) {
      UiSnack.showError('שגיאה בהשבתת התוסף: ${e.toString()}');
    }
  }

  Future<void> _onSetPluginPermissionRequested(
      SetPluginPermissionRequested event,
      Emitter<PluginSystemState> emit) async {
    try {
      await repository.setPermission(
          event.pluginId, event.permission, event.granted);
      final permissions = await repository.getPluginPermissions(event.pluginId);
      final grantedPermissions = permissions
          .where((permission) => permission.granted)
          .map((permission) => permission.permission)
          .toList();
      PluginRuntimeDispatcher.instance.dispatchEvent(
        'plugin.permissions_changed',
        {'permissions': grantedPermissions},
      );
      add(LoadPlugins());
    } catch (e) {
      UiSnack.showError('שגיאה בעדכון הרשאה: ${e.toString()}');
    }
  }

  Future<void> _onLoadDevelopmentPluginRequested(
      LoadDevelopmentPluginRequested event, Emitter<PluginSystemState> emit) async {
    try {
      await devLoader.loadDevelopmentPlugin(event.directoryPath);
      add(LoadPlugins());
      UiSnack.showSuccess('תוסף פיתוח נטען בהצלחה');
    } catch (e) {
      UiSnack.showError('שגיאה בטעינת תוסף פתוח: ${e.toString()}');
    }
  }

  Future<void> _onDetachDevelopmentPluginRequested(
      DetachDevelopmentPluginRequested event, Emitter<PluginSystemState> emit) async {
    try {
      await repository.detachDevelopmentPlugin(event.pluginId);
      devWatchService.stopWatcher(event.pluginId);
      add(LoadPlugins());
    } catch (e) {
      UiSnack.showError('שגיאה בניתוק התוסף: ${e.toString()}');
    }
  }

  Future<void> _onReloadDevelopmentPluginRequested(
      ReloadDevelopmentPluginRequested event, Emitter<PluginSystemState> emit) async {
    PluginRuntimeDispatcher.instance.reloadPlugin(event.pluginId);
  }

  Future<void> _onDevelopmentPluginManifestChanged(
      DevelopmentPluginManifestChanged event, Emitter<PluginSystemState> emit) async {
    try {
      final plugin = await repository.getPlugin(event.pluginId);
      if (plugin != null && plugin.isDevelopment && plugin.devRootPath != null) {
        await devLoader.loadDevelopmentPlugin(plugin.devRootPath!);
        add(LoadPlugins());
        PluginRuntimeDispatcher.instance.reloadPlugin(event.pluginId);
      }
    } catch (e) {
      PluginRuntimeDispatcher.instance.reloadPlugin(event.pluginId);
    }
  }
}
