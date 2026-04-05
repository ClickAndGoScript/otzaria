import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/services/plugin_manifest_validator.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_handler.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:collection';
import 'package:path/path.dart' as p;
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_adapter.dart';
import 'package:otzaria/tools/calendar/ulits/calendar_cubit.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:otzaria/utils/book_open_coordinator.dart';
import 'package:otzaria/widgets/custom_ui_components.dart';
import 'package:otzaria/plugins/view/plugin_dev_error_view.dart';

// ---------------------------------------------------------------------------
// Stub SDK — injected at AT_DOCUMENT_START before any page JS runs.
// Queues all Otzaria.on() calls so they survive the async boot gap.
// ---------------------------------------------------------------------------
const String _sdkStub = r'''
(function () {
  var _queue = [];
  var _realSdk = null;

  window.Otzaria = {
    call: function (method, payload) {
      if (_realSdk) return _realSdk.call(method, payload);
      return Promise.reject(new Error('Otzaria SDK not ready yet'));
    },
    on: function (event, cb) {
      if (_realSdk) { _realSdk.on(event, cb); }
      else { _queue.push({ event: event, cb: cb }); }
    },
    off: function (event, cb) {
      if (_realSdk) _realSdk.off(event, cb);
    },
    /* Called by Flutter once the real SDK + boot payload are ready */
    _boot: function (sdk, payload) {
      _realSdk = sdk;
      // Re-register all listeners that were queued before boot
      _queue.forEach(function (item) { sdk.on(item.event, item.cb); });
      _queue = [];
      window.dispatchEvent(new CustomEvent('plugin.boot', { detail: payload }));
      window.dispatchEvent(new CustomEvent('plugin.ready', { detail: null }));
    }
  };

  // Block window.open for security
  window.open = function () {
    console.error('window.open is locked for security.');
    return null;
  };
})();
''';

class PluginTabPage extends StatefulWidget {
  final InstalledPlugin plugin;

  const PluginTabPage({super.key, required this.plugin});

  @override
  State<PluginTabPage> createState() => _PluginTabPageState();
}

class _PluginTabPageState extends State<PluginTabPage> {
  InAppWebViewController? webViewController;
  late String localHtmlPath;
  late final PluginBridgeHandler _bridge;
  late final PluginBridgeAdapter _adapter;
  late final PluginRegistryRepository _pluginRegistryRepository;
  bool _hasError = false;
  String? _devErrorMessage;

  // Cache PackageInfo so the async gap in onLoadStop never crosses a dispose
  static PackageInfo? _cachedPackageInfo;

  @override
  void initState() {
    super.initState();
    localHtmlPath =
        '${widget.plugin.resolvedRootPath}/${widget.plugin.entrypointPath}';
    final historyBloc = context.read<HistoryBloc>();
    final tabsBloc = context.read<TabsBloc>();
    final navigationBloc = context.read<NavigationBloc>();
    final calendarCubit = context.read<CalendarCubit>();
    final workspaceBloc = context.read<WorkspaceBloc>();
    final searchRepository = SearchRepository();
    final personalNotesRepository = PersonalNotesRepository();
    final pluginRegistryRepository = PluginRegistryRepository();

    final dependencies = PluginBridgeDependencies(
      historyBloc: historyBloc,
      tabsBloc: tabsBloc,
      navigationBloc: navigationBloc,
      calendarCubit: calendarCubit,
      workspaceBloc: workspaceBloc,
      searchRepository: searchRepository,
      personalNotesRepository: personalNotesRepository,
      bookOpenCoordinator: BookOpenCoordinator(
        tabsBloc: tabsBloc,
        historyBloc: historyBloc,
        navigationBloc: navigationBloc,
      ),
      themePayloadBuilder: () {
        if (!mounted) {
          return {
            'mode': 'light',
            'colorScheme': <String, dynamic>{},
            'typography': <String, dynamic>{},
          };
        }
        return buildThemePayload(context);
      },
      showConfirmDialog: ({
        required String title,
        required String content,
      }) async {
        if (!mounted) return false;
        return await showTwoActionsDialog(
              context: context,
              title: title,
              content: content,
              cancelText: 'ביטול',
              confirmText: 'אישור',
            ) ==
            true;
      },
      showWarningDialog: ({
        required String title,
        required String content,
        required String subtitle,
      }) async {
        if (!mounted) return false;
        return await showWarningDialog(
              context: context,
              title: title,
              content: content,
              subtitle: subtitle,
              cancelText: 'ביטול',
              confirmText: 'המשך',
            ) ==
            true;
      },
    );

    _pluginRegistryRepository = pluginRegistryRepository;
    _adapter = PluginBridgeAdapter(
      widget.plugin,
      dependencies: dependencies,
      pluginRepository: pluginRegistryRepository,
    );
    _bridge = PluginBridgeHandler(
      widget.plugin,
      adapter: _adapter,
      registry: pluginRegistryRepository,
    );
    // Pre-fetch so onLoadStop has no async gap
    _ensurePackageInfo();
    
    PluginRuntimeDispatcher.instance.registerReloadCallback(
      widget.plugin.pluginId,
      _reloadFromDisk,
    );
  }

  Future<void> _reloadFromDisk() async {
    if (!mounted) return;
    if (!widget.plugin.isDevelopment) return;

    try {
      await _ensurePackageInfo();
      final manifestFile = File(p.join(widget.plugin.resolvedRootPath, 'manifest.json'));
      if (!manifestFile.existsSync()) {
        setState(() => _devErrorMessage = 'קובץ manifest.json חסר בתיקייה.');
        return;
      }
      final manifestStr = await manifestFile.readAsString();
      final manifestJson = jsonDecode(manifestStr);
      
      // Perform strict manifest validation
      final manifest = PluginManifest.fromJson(manifestJson);
      
      await PluginManifestValidator.validateManifest(
        manifest: manifest,
        directoryPath: widget.plugin.resolvedRootPath,
        currentAppVersion: _cachedPackageInfo?.version,
      );
      
      if (manifest.id != widget.plugin.pluginId) {
        setState(() => _devErrorMessage = 'מזהה התוסף (id) השתנה.\nמצופה: ${widget.plugin.pluginId}\nנמצא: ${manifest.id}\nשינוי ID דורש התקנה מחדש.');
        return;
      }

      setState(() => _devErrorMessage = null);
      
      try {
        await InAppWebViewController.clearAllCache();
      } catch (_) {}

      localHtmlPath = p.join(widget.plugin.resolvedRootPath, manifest.entrypoint);
      await webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri.uri(Uri.file(localHtmlPath))));
    } catch (e) {
      if (mounted) setState(() => _devErrorMessage = 'שגיאה בלתי צפויה בריענון התוסף: $e');
    }
  }

  Future<void> _ensurePackageInfo() async {
    _cachedPackageInfo ??= await PackageInfo.fromPlatform();
  }

  @override
  void dispose() {
    PluginRuntimeDispatcher.instance
        .unregisterController(widget.plugin.pluginId);
    PluginRuntimeDispatcher.instance
        .unregisterReloadCallback(widget.plugin.pluginId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.plugin.enabled) {
      return Center(
        child: Text(
          'התוסף כבוי על ידי המשתמש ולא ניתן להציגו.',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      );
    }

    if (_devErrorMessage != null) {
      return PluginDevErrorView(
        plugin: widget.plugin,
        errorMessage: _devErrorMessage!,
      );
    }

    if (_hasError) {
      return Center(child: Text('שגיאה בטעינת הקובץ: $localHtmlPath'));
    }

    if (!File(localHtmlPath).existsSync()) {
      return const SizedBox.shrink(); // התוסף כבר הוסר — הטאב ייסגר בקרוב
    }

    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri.uri(Uri.file(localHtmlPath))),
      initialSettings: InAppWebViewSettings(
        allowFileAccessFromFileURLs: false,
        allowUniversalAccessFromFileURLs: false,
        useShouldOverrideUrlLoading: true,
        useShouldInterceptRequest: true,
        cacheEnabled: !widget.plugin.isDevelopment,
        clearCache: widget.plugin.isDevelopment,
      ),
      // Stub SDK — injected BEFORE any page JS runs
      initialUserScripts: UnmodifiableListView<UserScript>([
        UserScript(
          source: _sdkStub,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
      ]),
      onWebViewCreated: (controller) {
        webViewController = controller;
        PluginRuntimeDispatcher.instance
            .registerController(widget.plugin.pluginId, controller);
        _bridge.register(controller);
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        final uri = navigationAction.request.url;
        if (uri == null) return NavigationActionPolicy.CANCEL;

        if (uri.scheme == 'file') {
          final normalizedUri = p.normalize(uri.toFilePath());
          final normalizedInstall = p.normalize(widget.plugin.resolvedRootPath);
          if (p.isWithin(normalizedInstall, normalizedUri) ||
              normalizedUri == normalizedInstall) {
            return NavigationActionPolicy.ALLOW;
          }
        } else if (uri.scheme == 'data' ||
            uri.scheme == 'blob' ||
            uri.scheme == 'about') {
          return NavigationActionPolicy.ALLOW;
        }

        if (uri.scheme == 'http' || uri.scheme == 'https') {
          if (widget.plugin.manifest.networkEnabled) {
            final granted = await _pluginRegistryRepository.getPermission(
              widget.plugin.pluginId,
              'network.access',
            );
            if (granted == true) {
              final allowlist = widget.plugin.manifest.networkAllowlist;
              if (allowlist.any((domain) =>
                  uri.host == domain || uri.host.endsWith('.$domain'))) {
                return NavigationActionPolicy.ALLOW;
              }
            }
          }
        }

        return NavigationActionPolicy.CANCEL;
      },
      shouldInterceptRequest: (controller, request) async {
        final uri = request.url;
        if (uri.scheme == 'file') {
          final normalizedUri = p.normalize(uri.toFilePath());
          final normalizedInstall = p.normalize(widget.plugin.resolvedRootPath);
          if (!p.isWithin(normalizedInstall, normalizedUri) &&
              normalizedUri != normalizedInstall) {
            return WebResourceResponse(
                statusCode: 403, reasonPhrase: 'Forbidden');
          }
        }
        if (uri.scheme == 'http' || uri.scheme == 'https') {
          if (widget.plugin.manifest.networkEnabled) {
            final granted = await _pluginRegistryRepository.getPermission(
              widget.plugin.pluginId,
              'network.access',
            );
            if (granted == true) {
              final allowlist = widget.plugin.manifest.networkAllowlist;
              if (!allowlist.any((domain) =>
                  uri.host == domain || uri.host.endsWith('.$domain'))) {
                return WebResourceResponse(
                    statusCode: 403, reasonPhrase: 'Forbidden');
              }
              return null;
            }
          }
          return WebResourceResponse(
              statusCode: 403, reasonPhrase: 'Forbidden');
        }
        return null;
      },
      onLoadStop: (controller, url) async {
        // לוכד theme לפני ה-await (context חייב להישמר synchronously)
        final theme = buildThemePayload(context);

        // Use cached PackageInfo — avoids async gap crossing a dispose
        final packageInfo =
            _cachedPackageInfo ?? await PackageInfo.fromPlatform();
        if (!mounted) return;
        final permissions = await _pluginRegistryRepository.getPluginPermissions(
          widget.plugin.pluginId,
        );
        if (!mounted) return;
        final bootPayload = {
          'plugin': {
            'id': widget.plugin.pluginId,
            'version': widget.plugin.version,
          },
          'app': {
            'version': packageInfo.version,
            'platform': Platform.operatingSystem,
            'locale': 'he-IL',
            'textDirection': 'rtl',
          },
          'theme': theme,
          'permissions': permissions
              .where((permission) => permission.granted)
              .map((permission) => permission.permission)
              .toList(),
        };

        final jsonPayload = jsonEncode(bootPayload);

        // Real SDK — injected after load, calls _boot() which re-plays queued
        // Otzaria.on() calls and then fires plugin.boot
        await controller.evaluateJavascript(source: '''
(function () {
  var _ls = {};
  var realSdk = {
    call: function (method, payload) {
      return window.flutter_inappwebview.callHandler('otzaria_rpc', {
        method: method,
        payload: payload || {}
      });
    },
    on: function (event, cb) {
      if (!_ls[event]) _ls[event] = [];
      var w = function (e) { cb(e.detail); };
      _ls[event].push({ orig: cb, wrap: w });
      window.addEventListener(event, w);
    },
    off: function (event, cb) {
      var list = _ls[event];
      if (!list) return;
      for (var i = 0; i < list.length; i++) {
        if (list[i].orig === cb) {
          window.removeEventListener(event, list[i].wrap);
          list.splice(i, 1);
          break;
        }
      }
    }
  };
  window.Otzaria._boot(realSdk, $jsonPayload);
})();
''');
      },
      onReceivedError: (controller, request, error) {
        if (mounted) setState(() => _hasError = true);
      },
      onConsoleMessage: (controller, consoleMessage) {
        if (consoleMessage.messageLevel == ConsoleMessageLevel.ERROR ||
            consoleMessage.messageLevel == ConsoleMessageLevel.WARNING) {
          PluginSystemDatabase.instance.writeLog(widget.plugin.pluginId,
              consoleMessage.messageLevel.toString(), consoleMessage.message);
        }
        debugPrint(
            'Plugin [${widget.plugin.pluginId}]: ${consoleMessage.message}');
      },
    );
  }
}
