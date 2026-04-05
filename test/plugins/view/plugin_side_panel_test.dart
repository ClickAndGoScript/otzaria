import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/plugins/view/plugin_side_panel.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:path/path.dart' as p;
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_permission_grant.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mockito/mockito.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:package_info_plus/package_info_plus.dart';

// Mock FilePicker instance to avoid MissingPluginException and LateInitializationError
class FakeFilePicker extends Mock with MockPlatformInterfaceMixin implements FilePicker {
  final String fakeDirectoryPath;
  FakeFilePicker(this.fakeDirectoryPath);

  @override
  Future<FilePickerResult?> pickFiles({
    bool allowCompression = true,
    bool allowMultiple = false,
    List<String>? allowedExtensions,
    int compressionQuality = 30,
    String? dialogTitle,
    String? initialDirectory,
    bool lockParentWindow = false,
    dynamic Function(FilePickerStatus)? onFileLoading,
    bool readSequential = false,
    FileType type = FileType.any,
    bool withData = false,
    bool withReadStream = false,
  }) async {
    return FilePickerResult([PlatformFile(path: fakeDirectoryPath, name: 'dir', size: 0)]);
  }

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    String? initialDirectory,
    bool lockParentWindow = false,
  }) async {
    return fakeDirectoryPath;
  }
}

class FakePluginRegistryRepository extends Mock implements PluginRegistryRepository {
  List<InstalledPlugin> plugins = [];
  
  @override
  Future<void> saveDevelopmentPlugin(InstalledPlugin plugin) async {
    plugins.add(plugin);
  }

  @override Future<List<InstalledPlugin>> getAllPlugins() async => plugins;
  @override Future<List<InstalledPlugin>> getDevelopmentPlugins() async => plugins;
  @override Future<InstalledPlugin?> getPlugin(String id) async => null;
  @override Future<bool?> getPermission(String id, String perm) async => true;
  @override Future<void> setPermission(String id, String perm, bool granted) async {}
  @override Future<List<PluginPermissionGrant>> getPluginPermissions(String id) async => [];
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    PackageInfo.setMockInitialValues(
      appName: 'Otzaria',
      packageName: 'com.otzaria.app',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets('PluginSidePanel shows dev tools explicitly when flag is true', (WidgetTester tester) async {
    final mockRepo = FakePluginRegistryRepository();
    final bloc = PluginSystemBloc(repository: mockRepo);
    
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<PluginSystemBloc>.value(
            value: bloc,
            child: const PluginSidePanel(showDevTools: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(FluentIcons.folder_add_24_regular), findsOneWidget);
  });

  testWidgets('PluginSidePanel hides dev tools explicitly when flag is false', (WidgetTester tester) async {
    final mockRepo = FakePluginRegistryRepository();
    final bloc = PluginSystemBloc(repository: mockRepo);
    
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: Scaffold(
          body: BlocProvider<PluginSystemBloc>.value(
            value: bloc,
            child: const PluginSidePanel(showDevTools: false),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(FluentIcons.folder_add_24_regular), findsNothing);
  });

  testWidgets('PluginSidePanel triggers picker and bloc on dev button tap', (WidgetTester tester) async {
    // Pre-cache package info to prevent method channel hang during widget test async pumped frames
    await PackageInfo.fromPlatform();
    
    final mockRepo = FakePluginRegistryRepository();
    final bloc = PluginSystemBloc(repository: mockRepo);
    
    final tempDir = Directory.systemTemp.createTempSync('otzaria_test_sidepanel');
    final manifestFile = File(p.join(tempDir.path, 'manifest.json'));
    manifestFile.writeAsStringSync(jsonEncode({
      'schemaVersion': 1,
      'id': 'test.ui.plugin',
      'version': '1.0.0',
      'name': 'UI Dev Plugin',
      'entrypoint': 'index.html',
      'permissions': [],
      'minAppVersion': '1.0.0',
      'description': 'test',
      'author': 'tester',
      'homepage': 'https://test.com',
      'sdkVersion': '1.0.0',
      'networkEnabled': false,
      'networkAllowlist': [],
      'toolTabTitle': 'Tab',
      'toolTabOrder': 0,
      'publishedDataTypes': []
    }));
    File(p.join(tempDir.path, 'index.html')).createSync();

    // Use our custom Fake FilePicker instead of method channels
    FilePicker.platform = FakeFilePicker(tempDir.path);

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: Scaffold(
          body: BlocProvider<PluginSystemBloc>.value(
            value: bloc,
            child: const PluginSidePanel(showDevTools: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Register the stream expectation BEFORE the action that triggers it.
    // emitsThrough allows intermediate states (e.g. PluginSystemLoading) before the target.
    final loadedExpectation = expectLater(
      bloc.stream,
      emitsThrough(isA<PluginSystemLoaded>()),
    );

    await tester.tap(find.byIcon(FluentIcons.folder_add_24_regular));
    await tester.pump();

    // The DevLoader uses real dart:io which needs real async — runAsync lets
    // the Dart event loop run freely while we wait for the stream to emit.
    await tester.runAsync(() => loadedExpectation);

    // Flush the UiSnack overlay timer so the test teardown doesn't complain.
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));

    // Verify UI is still intact
    expect(find.byIcon(FluentIcons.folder_add_24_regular), findsOneWidget);

    // Deep verification: the repository received the correct plugin data
    expect(mockRepo.plugins.isNotEmpty, isTrue);
    expect(mockRepo.plugins.first.pluginId, 'test.ui.plugin');
    expect(mockRepo.plugins.first.name, 'UI Dev Plugin');
    expect(mockRepo.plugins.first.sourceType, 'development');

    tempDir.deleteSync(recursive: true);
  });
}
