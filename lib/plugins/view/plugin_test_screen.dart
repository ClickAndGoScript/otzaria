import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class PluginTestScreen extends StatefulWidget {
  const PluginTestScreen({super.key});

  @override
  State<PluginTestScreen> createState() => _PluginTestScreenState();
}

class _PluginTestScreenState extends State<PluginTestScreen> {
  InAppWebViewController? webViewController;
  String? localHtmlPath;

  @override
  void initState() {
    super.initState();
    _prepareLocalHtml();
  }

  Future<void> _prepareLocalHtml() async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/test_plugin.html');
    await file.writeAsString('''
<!DOCTYPE html>
<html lang="he" dir="rtl">
<head>
    <meta charset="UTF-8">
    <title>Test Plugin</title>
    <style>
        body { font-family: system-ui; text-align: center; margin-top: 50px; background-color: #f3f3f3; }
        button { padding: 10px 20px; font-size: 16px; cursor: pointer; }
        #output { margin-top: 20px; color: blue; }
    </style>
</head>
<body>
    <h1>תוסף ניסיון</h1>
    <button onclick="testBridge()">שלח הודעה ל-Dart</button>
    <div id="output"></div>

    <script>
        window.testBridge = function() {
            window.flutter_inappwebview.callHandler('otzariaHostCall', { message: 'Hello from JS!' })
            .then(function(result) {
                document.getElementById('output').innerText = 'התקבלה תשובה: ' + JSON.stringify(result);
            });
        };
        
        window.receiveFromDart = function(msg) {
            document.getElementById('output').innerText = 'קריאה מ-Dart: ' + msg;
            return "OK";
        };
    </script>
</body>
</html>
''');
    setState(() {
      localHtmlPath = file.path;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (localHtmlPath == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('בדיקת תוסף (WebView POC)', textDirection: TextDirection.rtl),
        actions: [
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: () async {
              if (webViewController != null) {
                final result = await webViewController!.evaluateJavascript(source: 'window.receiveFromDart("Hello from Dart!")');
                if (mounted) UiSnack.show('תוצאה מהתוסף: $result');
              }
            },
          )
        ],
      ),
      body: InAppWebView(
        initialFile: localHtmlPath,
        initialSettings: InAppWebViewSettings(
          allowFileAccessFromFileURLs: true,
          allowUniversalAccessFromFileURLs: true,
        ),
        onWebViewCreated: (controller) {
          webViewController = controller;
          controller.addJavaScriptHandler(
            handlerName: 'otzariaHostCall',
            callback: (args) {
              if (mounted) UiSnack.show("התקבלה קריאה מ-JS: ${args[0]['message']}");
              return {'status': 'ok', 'dartResponse': 'Message received'};
            },
          );
        },
        onConsoleMessage: (controller, consoleMessage) {
          debugPrint('Plugin Web Console: \${consoleMessage.message}');
        },
      ),
    );
  }
}
