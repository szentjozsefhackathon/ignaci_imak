import 'package:diacritic/diacritic.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:slugify/slugify.dart';

part 'types.g.dart';

typedef Json = Map<String, dynamic>;

@JsonEnum(fieldRename: FieldRename.screamingSnake)
enum PrayerStepType { fix, flex }

typedef PrayerWithGroup = ({Prayer prayer, PrayerGroup group});

extension PrayerWithGroupExtensions on PrayerWithGroup {
  String get slug => '${group.slug}/${prayer.slug}';
}

typedef PrayerWithSteps = ({Prayer prayer, List<PrayerStep> steps});

extension PrayerWithStepsExtensions on PrayerWithSteps {
  Duration get totalTime =>
      steps.fold(Duration.zero, (t, step) => t += step.time);
}

abstract class PrayerBase {
  PrayerBase({required this.title, required this.image})
    : slug = slugify(removeDiacritics(title));

  // TODO: remove this when server data includes slug
  @JsonKey(includeFromJson: false)
  final String slug;
  final String title;
  final String image;
}

@JsonSerializable(createToJson: false)
class PrayerGroup extends PrayerBase {
  PrayerGroup({required super.title, required super.image});

  factory PrayerGroup.fromJson(Json json) => _$PrayerGroupFromJson(json);
}

@JsonSerializable(createToJson: false)
class Prayer extends PrayerBase {
  Prayer({
    required this.group,
    required super.title,
    required this.description,
    required super.image,
    required this.voiceOptions,
    required this.minTime,
  });

  factory Prayer.fromJson(Json json, {required PrayerGroup group}) =>
      _$PrayerFromJson({...json, 'group': group.slug});

  final String description;
  @JsonKey(name: 'minTimeInMinutes', fromJson: _minutesToDuration)
  final Duration minTime;
  @JsonKey(name: 'voice_options')
  final List<String> voiceOptions;
  final String group;

  static Duration _minutesToDuration(int minutes) => Duration(minutes: minutes);
}

@JsonSerializable(createToJson: false)
class PrayerStep {
  PrayerStep({
    this.id,
    required this.index,
    required this.description,
    required this.type,
    required this.time,
    required this.voices,
    required this.prayer,
  });

  factory PrayerStep.fromJson(
    Json json, {
    required Prayer prayer,
    required int index,
  }) => _$PrayerStepFromJson({...json, 'prayer': prayer.slug, 'index': index});

  @JsonKey(includeFromJson: false)
  final int? id;
  final int index;
  final String description;
  final PrayerStepType type;
  @JsonKey(name: 'timeInSeconds', fromJson: _secondsToDuration)
  final Duration time;
  final List<String> voices;
  final String prayer;

  static Duration _secondsToDuration(int seconds) => Duration(seconds: seconds);
}
