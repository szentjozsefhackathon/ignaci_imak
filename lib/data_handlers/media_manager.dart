import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/common.dart';
import '../data/media_data.dart';
import '../urls.dart';
import 'data_set_manager.dart';

class MediaManager extends ListDataSetManagerBase<MediaData> {
  MediaManager({required super.dataKey, required super.dataUrlEndpoint})
    : super(logName: 'MediaManager', fromJson: MediaData.fromJson);

  final _localFileCache = <String, File>{};

  Future<bool> syncFiles(
    DataList<MediaData> serverFiles, {
    required bool stopOnError,
  }) async {
    assert(!kIsWeb, 'syncFiles is not supported on web');

    // Get local media data from file system
    final localFiles = await _getLocalFiles();

    // Find files to delete
    final serverFileNames = serverFiles.map((file) => file.name).toSet();
    final filesToDelete =
        localFiles
            .where((file) => !serverFileNames.contains(file.name))
            .toList();
    // Delete files
    await Future.forEach(filesToDelete, _deleteFile);

    // Find files to update
    final filesToAddOrUpdate =
        serverFiles.where((serverFile) {
          // Find the corresponding local file
          final localFile = localFiles.firstWhereOrNull(
            (file) => file.name == serverFile.name,
          );
          // Check if the file does not exist locally or if the server file is newer
          return localFile == null ||
              serverFile.lastModified.isAfter(localFile.lastModified);
        }).toList();

    // Add or update files
    // TODO: how to reduce http requests?
    bool success = true;
    for (final file in filesToAddOrUpdate) {
      success &= await _downloadAndSaveFile(file);
      if (!success && stopOnError) {
        return false;
      }
    }
    return success;
  }

  Future<List<MediaData>> _getLocalFiles({bool ensureExists = true}) async {
    final directory = await _getLocalPath(ensureExists: ensureExists);

    final list = <MediaData>[];
    if (directory.existsSync()) {
      final files = directory
          .list(recursive: true, followLinks: false)
          .where((entity) => entity is File);
      await for (final file in files) {
        final fileStat = await file.stat();
        list.add(
          MediaData(
            name: file.uri.pathSegments.last,
            path: file.path,
            size: fileStat.size,
            lastModified: fileStat.modified,
          ),
        );
      }
    } else {
      log.warning('Directory does not exist: ${directory.path}');
    }

    return list;
  }

  Uri getDownloadUri(String name) => Uri.parse(mediaApiUrl(dataKey, name));

  Future<bool> _downloadAndSaveFile(MediaData m) async {
    try {
      final response = await http.get(getDownloadUri(m.name));
      if (response.statusCode == 200) {
        final file = await _getLocalFile(m.name, checkExists: false);
        await file.writeAsBytes(response.bodyBytes);
        _localFileCache[m.name] = file;
        //log.info('Saved file $m to ${file.path}');
        return true;
      } else {
        log.severe(
          'Failed to download $m, status code: ${response.statusCode}',
        );
      }
    } catch (e) {
      log.severe('Error during sync $m: $e');
    }
    return false;
  }

  Future<bool> _deleteFile(MediaData m) async {
    try {
      _localFileCache.remove(m.name);
      final file = await _getLocalFile(m.name, checkExists: false);
      if (file.existsSync()) {
        await file.delete();
      }
      //log.severe('Deleted file $m at ${file.path}');
      return true;
    } catch (e) {
      log.severe('Error deleting file $m: $e');
    }
    return false;
  }

  Future<File> _getLocalFile(String name, {required bool checkExists}) async {
    assert(!kIsWeb, 'getLocalFile is not supported on web');

    final directory = await _getLocalPath();
    final file = File(p.join(directory.path, name));
    if (checkExists && !file.existsSync()) {
      throw FileSystemException('$name nem található', file.path);
    }
    return file;
  }

  Future<File> getLocalFile(String name) async {
    if (_localFileCache.containsKey(name)) {
      return _localFileCache[name]!;
    }
    final file = await _getLocalFile(name, checkExists: true);
    _localFileCache[name] = file;
    return file;
  }

  Future<Directory> _getLocalPath({bool ensureExists = true}) async {
    final rootDirectory = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(rootDirectory.path, dataKey));
    if (ensureExists) {
      if (!directory.existsSync()) {
        await directory.create(recursive: true);
        log.info('Directory created: ${directory.path}');
      }
    }
    return directory;
  }

  Future<void> deleteLocalData() async {
    assert(!kIsWeb, 'deleteLocalData is not supported on web');

    final localFiles = await _getLocalFiles(ensureExists: false);
    await Future.forEach(localFiles, _deleteFile);
  }
}
