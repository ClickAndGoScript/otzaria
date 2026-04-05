import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_handler.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:collection';
import 'package:path/path.dart' as p;
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_adapter.dart' show buildThemePayload;

class PluginTabPage extends StatefulWidget {
  final InstalledPlugin plugin;

  const PluginTabPage({super.key, required this.plugin});

  @override
  State<PluginTabPage> createState() => _PluginTabPageState();
}

class _PluginTabPageState extends State<PluginTabPage> {
  InAppWebViewController? webViewController;
  late final String localHtmlPath;
  late final PluginBridgeHandler _bridge;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    localHtmlPath = '${widget.plugin.installPath}/${widget.plugin.entrypointPath}';
    _bridge = PluginBridgeHandler(widget.plugin);
  }

  @override
  void dispose() {
    PluginRuntimeDispatcher.instance.unregisterController(widget.plugin.pluginId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.plugin.enabled) {
      return Center(
        child: Text('התוסף כבוי על ידי המשתמש ולא ניתן להציגו.', style: TextStyle(color: Theme.of(context).colorScheme.error)),
      );
    }

    if (_hasError) {
      return Center(
        child: Text('שגיאה בטעינת הקובץ: $localHtmlPath'),
      );
    }

    if (!File(localHtmlPath).existsSync()) {
      return Center(
        child: Text('קובץ הכניסה של התוסף לא קיים בנתיב: $localHtmlPath'),
      );
    }

    return InAppWebView(
      initialFile: localHtmlPath,
      initialSettings: InAppWebViewSettings(
        allowFileAccessFromFileURLs: false,
        allowUniversalAccessFromFileURLs: false,
        useShouldOverrideUrlLoading: true,
        useShouldInterceptRequest: true,
      ),
      initialUserScripts: UnmodifiableListView<UserScript>([
        UserScript(
          source: '''
            window.open = function() {
              console.error('window.open is locked for security measures.');
              return null;
            };
          ''',
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
      ]),
      onWebViewCreated: (controller) {
        webViewController = controller;
        PluginRuntimeDispatcher.instance.registerController(widget.plugin.pluginId, controller);
        _bridge.register(controller);
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        final uri = navigationAction.request.url;
        if (uri == null) return NavigationActionPolicy.CANCEL;

        if (uri.scheme == 'file') {
          final normalizedUri = p.normalize(uri.toFilePath());
          final normalizedInstall = p.normalize(widget.plugin.installPath);
          if (p.isWithin(normalizedInstall, normalizedUri) || normalizedUri == normalizedInstall) {
            return NavigationActionPolicy.ALLOW;
          }
        } else if (uri.scheme == 'data' || uri.scheme == 'blob' || uri.scheme == 'about') {
          return NavigationActionPolicy.ALLOW;
        }

        // HTTP/HTTPS: require network.access in manifest AND granted in DB
        if (uri.scheme == 'http' || uri.scheme == 'https') {
          if (widget.plugin.manifest.networkEnabled) {
            final granted = await PluginRegistryRepository().getPermission(
                widget.plugin.pluginId, 'network.access');
            if (granted == true) {
              final allowlist = widget.plugin.manifest.networkAllowlist;
              if (allowlist.any((domain) => uri.host == domain || uri.host.endsWith('.$domain'))) {
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
          final normalizedInstall = p.normalize(widget.plugin.installPath);
          if (!p.isWithin(normalizedInstall, normalizedUri) && normalizedUri != normalizedInstall) {
            return WebResourceResponse(statusCode: 403, reasonPhrase: 'Forbidden');
          }
        }
        if (uri.scheme == 'http' || uri.scheme == 'https') {
          if (widget.plugin.manifest.networkEnabled) {
            final granted = await PluginRegistryRepository().getPermission(
                widget.plugin.pluginId, 'network.access');
            if (granted == true) {
              final allowlist = widget.plugin.manifest.networkAllowlist;
              if (!allowlist.any((domain) => uri.host == domain || uri.host.endsWith('.$domain'))) {
                return WebResourceResponse(statusCode: 403, reasonPhrase: 'Forbidden');
              }
              return null; // Allow
            }
          }
          return WebResourceResponse(statusCode: 403, reasonPhrase: 'Forbidden');
        }
        return null;
      },
      onLoadStop: (controller, url) async {
        final theme = buildThemePayload(context);

        final packageInfo = await PackageInfo.fromPlatform();
        if (!mounted) return;
        final appVersion = packageInfo.version;

        // Build Boot Payload - full spec compliant
        final bootPayload = {
          'plugin': {
            'id': widget.plugin.pluginId,
            'version': widget.plugin.version,
          },
          'app': {
            'version': appVersion,
            'platform': Platform.operatingSystem,
            'locale': 'he-IL',
            'textDirection': 'rtl'
          },
          'theme': theme,
          'permissions': widget.plugin.manifest.permissions,
        };

        final jsonPayload = jsonEncode(bootPayload);

        // Inject JS API - full spec-compliant SDK
        await controller.evaluateJavascript(source: '''
          (function() {
            var _listeners = {};

            window.Otzaria = {
              call: function(methodName, payload) {
                return window.flutter_inappwebview.callHandler('otzaria_rpc', {
                  method: methodName,
                  payload: payload || {}
                });
              },
              on: function(event, cb) {
                if (!_listeners[event]) _listeners[event] = [];
                var wrapped = function(e) { cb(e.detail); };
                _listeners[event].push({ original: cb, wrapped: wrapped });
                window.addEventListener(event, wrapped);
              },
              off: function(event, cb) {
                var list = _listeners[event];
                if (!list) return;
                for (var i = 0; i < list.length; i++) {
                  if (list[i].original === cb) {
                    window.removeEventListener(event, list[i].wrapped);
                    list.splice(i, 1);
                    break;
                  }
                }
              }
            };

            window.dispatchEvent(new CustomEvent('plugin.boot', { detail: $jsonPayload }));
            window.dispatchEvent(new Event('plugin.ready'));
          })();
        ''');
      },
      onReceivedError: (controller, request, error) {
        setState(() {
          _hasError = true;
        });
      },
      onConsoleMessage: (controller, consoleMessage) {
        if (consoleMessage.messageLevel == ConsoleMessageLevel.ERROR || consoleMessage.messageLevel == ConsoleMessageLevel.WARNING) {
          PluginSystemDatabase.instance.writeLog(widget.plugin.pluginId, consoleMessage.messageLevel.toString(), consoleMessage.message);
        }
        debugPrint('Plugin [${widget.plugin.pluginId}]: ${consoleMessage.message}');
      },
    );
  }
}
