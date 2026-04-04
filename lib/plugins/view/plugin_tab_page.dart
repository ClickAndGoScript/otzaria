import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'dart:io';

class PluginTabPage extends StatefulWidget {
  final InstalledPlugin plugin;

  const PluginTabPage({super.key, required this.plugin});

  @override
  State<PluginTabPage> createState() => _PluginTabPageState();
}

class _PluginTabPageState extends State<PluginTabPage> {
  InAppWebViewController? webViewController;
  late final String localHtmlPath;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    localHtmlPath = '${widget.plugin.installPath}/${widget.plugin.entrypointPath}';
  }

  @override
  Widget build(BuildContext context) {
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
        allowFileAccessFromFileURLs: true,
        allowUniversalAccessFromFileURLs: true,
        // TODO: restrict network access per manifest
      ),
      onWebViewCreated: (controller) {
        webViewController = controller;
        // The real Host API bridge will be registered here in Phase 2
      },
      onReceivedError: (controller, request, error) {
        setState(() {
          _hasError = true;
        });
      },
      onConsoleMessage: (controller, consoleMessage) {
        debugPrint('Plugin [${widget.plugin.pluginId}]: ${consoleMessage.message}');
      },
    );
  }
}
