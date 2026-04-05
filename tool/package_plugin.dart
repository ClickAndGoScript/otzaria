// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:convert';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/services/plugin_manifest_validator.dart';

void main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart tool/package_plugin.dart <path_to_plugin_directory> [--force]');
    exit(1);
  }

  final dirPath = args[0];
  final dir = Directory(dirPath);
  final bool force = args.contains('--force');

  if (!dir.existsSync()) {
    print('Error: Directory does not exist: $dirPath');
    exit(1);
  }

  final manifestFile = File(p.join(dir.path, 'manifest.json'));
  if (!manifestFile.existsSync()) {
    print('Error: manifest.json not found in $dirPath. A valid plugin must have a manifest.json.');
    exit(1);
  }

  final manifestStr = manifestFile.readAsStringSync();
  late Map<String, dynamic> manifestJson;
  try {
    manifestJson = jsonDecode(manifestStr);
  } catch (e) {
    print('Error: manifest.json is not valid JSON.');
    exit(1);
  }

  late PluginManifest manifest;
  try {
    manifest = PluginManifest.fromJson(manifestJson);
  } catch (e) {
    print('Error: Failed to parse manifest.json into PluginManifest structure: $e');
    exit(1);
  }

  try {
    await PluginManifestValidator.validateManifest(
      manifest: manifest,
      directoryPath: dir.path,
      skipAppVersionValidation: true,
    );
  } catch (e) {
    print('Validation Error: $e');
    exit(1);
  }

  final outPath = p.join(dir.parent.path, '${manifest.id}-${manifest.version}.otzplugin');
  final outFile = File(outPath);

  if (outFile.existsSync() && !force) {
    print('Error: Output file already exists at $outPath');
    print('Use --force flag to overwrite.');
    exit(1);
  }

  final encoder = ZipFileEncoder();
  
  print('Packaging $dirPath into $outPath ...');
  
  encoder.create(outPath);
  encoder.addDirectory(dir, includeDirName: false);
  encoder.close();

  print('Done! Packaged successfully into: $outPath');
}
