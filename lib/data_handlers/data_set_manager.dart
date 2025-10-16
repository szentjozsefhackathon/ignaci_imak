import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/common.dart';
import 'exceptions.dart';

// TODO: move to Hive or SQLite

abstract class DataSetManagerBase<T extends ToJson, Item extends ToJson> {
  DataSetManagerBase({
    required String logName,
    required this.dataKey,
    required this.dataUrlEndpoint,
    required this.fromJson,
  }) : log = Logger('$logName ($dataKey)');

  final Logger log;
  final String dataKey;
  final Uri dataUrlEndpoint;
  final Item Function(Map<String, dynamic>) fromJson;

  T? _cachedServerData;
  T? get cachedServerData => _cachedServerData;

  T _decodeData(String data);

  Future<T> get serverData async {
    try {
      final response = await _fetchServerData();
      return _cachedServerData = _decodeData(response);
    } catch (e, s) {
      log.severe('Failed to load server data: $e', e, s);
      rethrow;
    }
  }

  Future<String> _fetchServerData() async {
    final client = SentryHttpClient(
      failedRequestStatusCodes: [SentryStatusCode.range(201, 599)],
    );
    try {
      final response = await client.get(dataUrlEndpoint);
      return response.body;
    } finally {
      client.close();
    }
  }
}

mixin LocalDataMixin<T extends ToJson, Item extends ToJson>
    on DataSetManagerBase<T, Item> {
  T? _cachedLocalData;
  T? get cachedLocalData => _cachedLocalData;

  Future<bool> get localDataExists async =>
      (_cachedLocalData ??= await _readLocalData()) != null;

  // Lazy initialization of data
  Future<T> get data async {
    try {
      T? local = (_cachedLocalData ??= await _readLocalData());
      if (local == null) {
        log.warning('No local data found');
        await downloadAndSaveData();
        local = _cachedLocalData = await _readLocalData();
        if (local == null) {
          throw DataLoadingException('Failed to load downloaded data');
        }
      }
      return local;
    } catch (e, s) {
      log.severe('Failed to load data: $e', e, s);
      rethrow;
    }
  }

  Future<void> downloadAndSaveData() async {
    try {
      final response = await _fetchServerData();
      await _saveLocalDataString(response);
      _cachedLocalData = _cachedServerData = _decodeData(response);
    } catch (e, s) {
      log.severe('Failed to download and save data: $e', e, s);
      rethrow;
    }
  }

  Future<void> saveLocalData(T data) async {
    await _saveLocalDataString(json.encode(data.toJson()));
    _cachedLocalData = data;
  }

  Future<void> _saveLocalDataString(String data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(dataKey, data);
    log.info('Data saved to storage');
  }

  Future<T?> _readLocalData() async {
    log.info('Reading data from storage');
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonData = prefs.getString(dataKey);

      if (jsonData == null) {
        log.warning('No local data found');
        return null;
      }
      return _decodeData(jsonData);
    } catch (e, s) {
      log.severe('Error reading local data', e, s);
      rethrow;
    }
  }

  Future<void> deleteLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(dataKey);
    _cachedLocalData = null;
    log.info('Data deleted');
  }
}

class DataSetManager<T extends DataDescriptor> extends DataSetManagerBase<T, T>
    with LocalDataMixin<T, T> {
  DataSetManager({
    required super.dataKey,
    required super.dataUrlEndpoint,
    required super.fromJson,
  }) : super(logName: 'DataSetManager');

  @override
  T _decodeData(String data) => fromJson(json.decode(data));
}

abstract class ListDataSetManagerBase<T extends DataDescriptor>
    extends DataSetManagerBase<DataList<T>, T> {
  ListDataSetManagerBase({
    required super.logName,
    required super.dataKey,
    required super.dataUrlEndpoint,
    required super.fromJson,
  });

  @override
  DataList<T> _decodeData(String data) =>
      DataList<T>.fromJson(json.decode(data), fromJson);
}

class ListDataSetManager<T extends DataDescriptor>
    extends ListDataSetManagerBase<T>
    with LocalDataMixin<DataList<T>, T> {
  ListDataSetManager({
    required super.dataKey,
    required super.dataUrlEndpoint,
    required super.fromJson,
  }) : super(logName: 'ListDataSetManager');

  @override
  DataList<T> _decodeData(String data) =>
      DataList<T>.fromJson(json.decode(data), fromJson);
}
