import 'package:equatable/equatable.dart';

import 'types.dart' show Json;

export 'types.dart' show Json;

class Versions extends Equatable {
  const Versions({
    required this.data,
    required this.images,
    required this.voices,
    required this.timestamp,
  });

  factory Versions.fromJson(Json json, {required DateTime timestamp}) =>
      Versions(
        data: json['data'] as String,
        images: json['images'] as String,
        voices: json['voices'] as String,
        timestamp: timestamp,
      );

  factory Versions.downloaded(
    Versions serverVersions, {
    bool data = false,
    bool images = false,
    bool voices = false,
  }) => Versions(
    data: data ? serverVersions.data : '',
    images: images ? serverVersions.data : '',
    voices: voices ? serverVersions.voices : '',
    timestamp: serverVersions.timestamp,
  );

  final String data;
  final String images;
  final String voices;

  /// UTC timestamp of the last check
  final DateTime timestamp;

  @override
  List<Object?> get props => [data, images, voices];

  Versions copyWith({
    String? data,
    String? images,
    String? voices,
    DateTime? timestamp,
  }) => Versions(
    data: data ?? this.data,
    images: images ?? this.images,
    voices: voices ?? this.voices,
    timestamp: timestamp ?? this.timestamp,
  );

  bool isUpdateAvailable(Versions v) =>
      (data.isNotEmpty && v.data.isNotEmpty && data != v.data) ||
      (images.isNotEmpty && v.images.isNotEmpty && images != v.images) ||
      (voices.isNotEmpty && v.voices.isNotEmpty && voices != v.voices);
}
