import 'package:logging/logging.dart';

import '../data/prayer_group.dart';
import '../data/versions.dart';
import '../env.dart';
import 'data_set_manager.dart';
import 'media_manager.dart';

// TODO: make this a povider

const kRequestTimeout = Duration(seconds: 10);

class DataManager {
  DataManager._() {
    versions = DataSetManager<Versions>(
      dataKey: 'versionsData',
      dataUrlEndpoint: Env.serverUri.replace(path: Env.serverCheckVersionsPath),
      fromJson: Versions.fromJson,
      requestTimeout: kRequestTimeout,
    );
    prayerGroups = ListDataSetManager<PrayerGroup>(
      dataKey: 'prayerGroupsData',
      dataUrlEndpoint: Env.serverUri.replace(path: Env.serverDownloadDataPath),
      fromJson: PrayerGroup.fromJson,
      requestTimeout: kRequestTimeout,
    );
    images = MediaManager(
      dataKey: 'images',
      dataUrlEndpoint: Env.serverUri.replace(
        path: '${Env.serverMediaPathPrefix}sync-images',
      ),
      requestTimeout: kRequestTimeout,
    );
    voices = MediaManager(
      dataKey: 'voices',
      dataUrlEndpoint: Env.serverUri.replace(
        path: '${Env.serverMediaPathPrefix}sync-voices',
      ),
      requestTimeout: kRequestTimeout,
    );
  }

  static DataManager? _instance;
  // ignore: prefer_constructors_over_static_methods
  static DataManager get instance => _instance ??= DataManager._();

  late final DataSetManager<Versions> versions;
  late final ListDataSetManager<PrayerGroup> prayerGroups;
  late final MediaManager images;
  late final MediaManager voices;

  static final log = Logger('DataManager');

  DateTime? _lastUpdateCheck;
  DateTime? get lastUpdateCheck => _lastUpdateCheck;

  Future<void> _updateLocalVersions(Versions newLocalVersions) async {
    await versions.saveLocalData(newLocalVersions);
    log.info('Local versions updated to ${newLocalVersions.toJson()}');
  }

  Future<Versions> checkForUpdates({required bool stopOnError}) async {
    final localVersionsExist = await versions.localDataExists;
    final localVersions = localVersionsExist ? (await versions.data) : null;
    log.info('Local versions: ${localVersions?.toJson()}');

    // Load server version data
    final serverVersions = await versions.serverData;
    log.info('Server versions: ${serverVersions.toJson()}');

    _lastUpdateCheck = DateTime.now();

    // Check if the data needs to be updated
    final oldVersion = localVersions?.data;
    final newVersion = serverVersions.data;
    if (oldVersion != newVersion) {
      await prayerGroups.downloadAndSaveData();
      log.info('Updating data from version $oldVersion to $newVersion');
      await _updateLocalVersions(
        localVersions == null
            ? serverVersions.copyWith(images: '', voices: '')
            : localVersions.copyWith(data: newVersion),
      );
    }
    return serverVersions;
  }

  Future<bool> updateImages(Versions serverVersions) async {
    final localVersions = versions.cachedLocalData;
    final oldVersion = localVersions?.images;
    final newVersion = serverVersions.images;
    if (oldVersion != newVersion) {
      final serverData = await images.serverData;
      if (await images.syncFiles(serverData, stopOnError: true)) {
        log.info('Image files updated from version $oldVersion to $newVersion');
        await _updateLocalVersions(
          localVersions == null
              ? serverVersions.copyWith(images: newVersion, voices: '')
              : localVersions.copyWith(images: newVersion),
        );
        return true;
      }
    }
    return false;
  }

  Future<bool> updateVoices(Versions serverVersions) async {
    final localVersions = versions.cachedLocalData;
    final oldVersion = localVersions?.voices;
    final newVersion = serverVersions.voices;
    if (oldVersion != newVersion) {
      final serverData = await voices.serverData;
      if (await voices.syncFiles(serverData, stopOnError: true)) {
        log.info('Voice files updated from version $oldVersion to $newVersion');
        await _updateLocalVersions(
          localVersions == null
              ? serverVersions.copyWith(voices: newVersion, images: '')
              : localVersions.copyWith(voices: newVersion),
        );
        return true;
      }
    }
    return false;
  }
}
