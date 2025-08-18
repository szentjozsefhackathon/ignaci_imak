import 'package:envied/envied.dart';

part 'env.g.dart';

@Envied(allowOptionalFields: true, useConstantCase: true)
abstract class Env {
  @EnviedField(defaultValue: 'dev')
  static const String sentryEnvironment = _Env.sentryEnvironment;

  @EnviedField(obfuscate: true)
  static final String? sentryDsn = _Env.sentryDsn;

  @EnviedField(defaultValue: '1.0')
  static const String sentryTracesSampleRate = _Env.sentryTracesSampleRate;

  @EnviedField(defaultValue: '1.0')
  static const String sentryProfilesSampleRate = _Env.sentryProfilesSampleRate;

  @EnviedField(defaultValue: '0.1')
  static const String sentrySessionSampleRate = _Env.sentrySessionSampleRate;

  @EnviedField(defaultValue: '1.0')
  static const String sentryOnErrorSampleRate = _Env.sentryOnErrorSampleRate;
}
