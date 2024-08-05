import 'dart:async';
import 'dart:convert';

import 'package:fimber/fimber.dart';
import 'package:flutter/services.dart';
import 'package:rxdart/rxdart.dart';
import 'package:vital_core/exceptions.dart';
import 'package:vital_core/samples.dart';
import 'package:vital_core/vital_core.dart';
import 'package:vital_health_platform_interface/vital_health_platform_interface.dart';

const _channel = MethodChannel('vital_health_connect');

class VitalHealthAndroid extends VitalHealthPlatform {
  static void registerWith() {
    VitalHealthPlatform.instanceFactory = () => VitalHealthAndroid();
  }

  final _statusSubject = PublishSubject<SyncStatus>();

  VitalHealthAndroid() : super() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case "status":
          {
            _statusSubject
                .add(mapArgumentsToStatus(call.arguments as List<dynamic>));
          }
      }
    });
  }

  @override
  Future<bool> isAvailable() async {
    return await _channel.invokeMethod('isAvailable');
  }

  @override
  Future<void> configureClient(
      String apiKey, Region region, Environment environment) async {
    Fimber.d('Health Connect configure $apiKey, $region $environment');

    await _channel.invokeMethod('configureClient', <String, dynamic>{
      "apiKey": apiKey,
      "region": region.name,
      "environment": environment.name,
    });
  }

  @override
  Future<void> configureHealth({required HealthConfig config}) async {
    Fimber.d('Health Connect configureHealthConnect');
    try {
      await _channel.invokeMethod('configureHealthConnect', <String, dynamic>{
        "logsEnabled": config.logsEnabled,
        "numberOfDaysToBackFill": config.numberOfDaysToBackFill,
        "syncOnAppStart": config.androidConfig.syncOnAppStart
      });
    } on Exception catch (e) {
      throw _mapException(e);
    }
  }

  @override
  Future<void> setUserId(String userId) async {
    try {
      await _channel.invokeMethod('setUserId', <String, dynamic>{
        "userId": userId,
      });
    } on Exception catch (e) {
      throw _mapException(e);
    }
  }

  @override
  Future<void> cleanUp() async {
    try {
      await _channel.invokeMethod('cleanUp');
    } on Exception catch (e) {
      throw _mapException(e);
    }
  }

  @override
  Future<PermissionOutcome> ask(List<HealthResource> readResources,
      List<HealthResourceWrite> writeResources) async {
    try {
      final outcome =
          await _channel.invokeMethod('askForResources', <String, dynamic>{
        "readResources": readResources.map((e) => e.name).toList(),
        "writeResources": writeResources.map((e) => e.name).toList(),
      });

      if (outcome == null) {
        return PermissionOutcome.success();
      } else {
        final error = jsonDecode(outcome);
        final code = error['code'];
        final message = error['message'];
        if (code == 'healthKitNotAvailable') {
          return PermissionOutcome.healthKitNotAvailable(message);
        } else if (code == 'UnsupportedResource') {
          return PermissionOutcome.failure('Unsupported Resource: $message');
        } else {
          return PermissionOutcome.failure('Unknown error');
        }
      }
    } on Exception catch (e) {
      throw _mapException(e);
    }
  }

  @override
  Future<void> syncData({List<HealthResource>? resources}) async {
    try {
      await _channel.invokeMethod('syncData', <String, dynamic>{
        "resources": resources?.map((e) => e.name).toList(),
      });
    } on Exception catch (e) {
      throw _mapException(e);
    }
  }

  @override
  Future<bool> hasAskedForPermission(HealthResource resource) async {
    try {
      return await _channel.invokeMethod('hasAskedForPermission', resource.name)
          as bool;
    } on Exception catch (e) {
      throw _mapException(e);
    }
  }

  @override
  Future<bool> isUserConnected(String provider) async {
    try {
      return await _channel.invokeMethod('isUserConnected', provider) as bool;
    } on Exception catch (e) {
      throw _mapException(e);
    }
  }

  @override
  Future<void> writeHealthData(HealthResourceWrite writeResource,
      DateTime startDate, DateTime endDate, double value) async {
    try {
      await _channel.invokeMethod('writeHealthData', <String, dynamic>{
        "resource": writeResource.name,
        "startDate": startDate.millisecondsSinceEpoch,
        "endDate": endDate.millisecondsSinceEpoch,
        "value": value,
      });
    } on Exception catch (e) {
      throw _mapException(e);
    }
  }

  @override
  Future<ProcessedData> read(
      HealthResource resource, DateTime startDate, DateTime endDate) async {
    try {
      if (resource == HealthResource.caffeine ||
          resource == HealthResource.mindfulSession) {
        throw UnsupportedResourceException(
            "Resource $resource is not supported on Android");
      }

      final result = await _channel.invokeMethod('read', <String, dynamic>{
        "resource": resource.name,
        "startDate": startDate.millisecondsSinceEpoch,
        "endDate": endDate.millisecondsSinceEpoch,
      });

      return _mapJsonToProcessedData(resource, jsonDecode(result));
    } on Exception catch (e) {
      throw _mapException(e);
    }
  }

  @override
  Future<bool> getPauseSynchronization() {
    return _channel
        .invokeMethod<bool>('getPauseSynchronization')
        .then((result) => result!);
  }

  @override
  Future<void> setPauseSynchronization(bool paused) {
    return _channel.invokeMethod('setPauseSynchronization', paused);
  }

  @override
  Future<bool> isBackgroundSyncEnabled() {
    return _channel
        .invokeMethod<bool>('isBackgroundSyncEnabled')
        .then((result) => result!);
  }

  @override
  Future<bool> enableBackgroundSync() {
    return _channel
        .invokeMethod<bool>('enableBackgroundSync')
        .then((result) => result!);
  }

  @override
  Future<void> disableBackgroundSync() {
    return _channel.invokeMethod('disableBackgroundSync');
  }

  @override
  Future<void> setSyncNotificationContent(SyncNotificationContent content) {
    final encodedContent = json.encode(content.toMap());
    return _channel.invokeMethod('setSyncNotificationContent', encodedContent);
  }

  @override
  Stream<SyncStatus> get status => _statusSubject.stream;
}

ProcessedData _mapJsonToProcessedData(
    HealthResource resource, Map<String, dynamic> json) {
  switch (resource) {
    case HealthResource.profile:
      return ProfileProcessedData(
        biologicalSex: json['biologicalSex'],
        dateOfBirth: json['dateOfBirth'] != null
            ? DateTime.fromMillisecondsSinceEpoch(
                (json['dateOfBirth'] as num).toInt(),
                isUtc: true)
            : null,
        heightInCm: json['heightInCm'],
      );
    case HealthResource.body:
      return BodyProcessedData(
        bodyMass: (json['bodyMass'] as List<dynamic>)
            .map((it) => _sampleFromJson(it))
            .whereType<LocalQuantitySample>()
            .toList(),
        bodyFatPercentage: (json['bodyFatPercentage'] as List<dynamic>)
            .map((it) => _sampleFromJson(it))
            .whereType<LocalQuantitySample>()
            .toList(),
      );
    case HealthResource.workout:
      return WorkoutProcessedData(
        workouts: (json['workouts'] as List<dynamic>)
            .map((it) => _workoutFromJson(it))
            .whereType<Workout>()
            .toList(),
      );
    case HealthResource.sleep:
      return SleepProcessedData(
        sleeps: (json['sleeps'] as List<dynamic>)
            .map((it) => _sleepFromJson(it))
            .whereType<Sleep>()
            .toList(),
      );
    case HealthResource.activity:
      return ActivityProcessedData(
        activities: (json['activities'] as List<dynamic>)
            .map((it) => _activityFromSwiftJson(it))
            .whereType<Activity>()
            .toList(),
      );
    case HealthResource.glucose:
      return TimeseriesProcessedData(
        timeSeries: (json['timeSeries'] as List<dynamic>)
            .map((it) => _sampleFromJson(it))
            .whereType<LocalQuantitySample>()
            .toList(),
      );
    case HealthResource.bloodPressure:
      return BloodPressureProcessedData(
        timeSeries: (json['timeSeries'] as List<dynamic>)
            .map((it) => _bloodPressureSampleFromJson(it))
            .whereType<LocalBloodPressureSample>()
            .toList(),
      );
    case HealthResource.heartRate:
      return TimeseriesProcessedData(
        timeSeries: (json['timeSeries'] as List<dynamic>)
            .map((it) => _sampleFromJson(it))
            .whereType<LocalQuantitySample>()
            .toList(),
      );
    case HealthResource.heartRateVariability:
      return TimeseriesProcessedData(
        timeSeries: (json['timeSeries'] as List<dynamic>)
            .map((it) => _sampleFromJson(it))
            .whereType<LocalQuantitySample>()
            .toList(),
      );
    case HealthResource.water:
      return TimeseriesProcessedData(
        timeSeries: (json['timeSeries'] as List<dynamic>)
            .map((it) => _sampleFromJson(it))
            .whereType<LocalQuantitySample>()
            .toList(),
      );
    case HealthResource.activeEnergyBurned:
      throw Exception("Not supported on Android");
    case HealthResource.basalEnergyBurned:
      throw Exception("Not supported on Android");
    case HealthResource.steps:
      throw Exception("Not supported on Android");
    case HealthResource.distanceWalkingRunning:
      throw Exception("Not supported on Android");
    case HealthResource.vo2Max:
      throw Exception("Not supported on Android");
    case HealthResource.caffeine:
      throw Exception("Not supported on Android");
    case HealthResource.mindfulSession:
      throw Exception("Not supported on Android");
    case HealthResource.temperature:
      throw Exception("Not supported on Android");
    case HealthResource.menstrualCycle:
      throw Exception("Not supported on Android");
    case HealthResource.respiratoryRate:
      throw Exception("Not supported on Android");
  }
}

Sleep? _sleepFromJson(Map<dynamic, dynamic>? json) {
  if (json == null) {
    return null;
  }
  return Sleep(
    id: json['id'],
    startDate: DateTime.fromMillisecondsSinceEpoch(
        (json['startDate'] as num).toInt(),
        isUtc: true),
    endDate: DateTime.fromMillisecondsSinceEpoch(
        (json['endDate'] as num).toInt(),
        isUtc: true),
    sourceBundle: json['sourceBundle'],
    deviceModel: json['deviceModel'],
    heartRate: <LocalQuantitySample>[],
    respiratoryRate: <LocalQuantitySample>[],
    heartRateVariability: <LocalQuantitySample>[],
    oxygenSaturation: <LocalQuantitySample>[],
    restingHeartRate: <LocalQuantitySample>[],
    sleepStages: SleepStages(
      awakeSleepSamples: json['sleepStages']['awakeSleepSamples'] != null
          ? (json['sleepStages']['awakeSleepSamples'] as List<dynamic>)
              .map((it) => _sampleFromJson(it))
              .whereType<LocalQuantitySample>()
              .toList()
          : <LocalQuantitySample>[],
      deepSleepSamples: json['sleepStages']['deepSleepSamples'] != null
          ? (json['sleepStages']['deepSleepSamples'] as List<dynamic>)
              .map((it) => _sampleFromJson(it))
              .whereType<LocalQuantitySample>()
              .toList()
          : <LocalQuantitySample>[],
      lightSleepSamples: json['sleepStages']['lightSleepSamples'] != null
          ? (json['sleepStages']['lightSleepSamples'] as List<dynamic>)
              .map((it) => _sampleFromJson(it))
              .whereType<LocalQuantitySample>()
              .toList()
          : <LocalQuantitySample>[],
      remSleepSamples: json['sleepStages']['remSleepSamples'] != null
          ? (json['sleepStages']['remSleepSamples'] as List<dynamic>)
              .map((it) => _sampleFromJson(it))
              .whereType<LocalQuantitySample>()
              .toList()
          : <LocalQuantitySample>[],
      unknownSleepSamples: json['sleepStages']['unknownSleepSamples'] != null
          ? (json['sleepStages']['unknownSleepSamples'] as List<dynamic>)
              .map((it) => _sampleFromJson(it))
              .whereType<LocalQuantitySample>()
              .toList()
          : <LocalQuantitySample>[],
      inBedSleepSamples: [],
      unspecifiedSleepSamples: [],
    ),
  );
}

Workout? _workoutFromJson(Map<dynamic, dynamic>? json) {
  if (json == null) {
    return null;
  }
  return Workout(
    id: json['id'],
    startDate: DateTime.fromMillisecondsSinceEpoch(
        (json['startDate'] as num).toInt(),
        isUtc: true),
    endDate: DateTime.fromMillisecondsSinceEpoch(
        (json['endDate'] as num).toInt(),
        isUtc: true),
    sourceBundle: json['sourceBundle'],
    deviceModel: json['deviceModel'],
    sport: json['sport'],
    caloriesInKiloJules: json['caloriesInKiloJules'],
    distanceInMeter: json['distanceInMeter'],
    heartRate: <LocalQuantitySample>[],
    respiratoryRate: <LocalQuantitySample>[],
  );
}

Activity? _activityFromSwiftJson(Map<dynamic, dynamic>? json) {
  if (json == null) {
    return null;
  }
  return Activity(
    distanceWalkingRunning: <LocalQuantitySample>[],
    activeEnergyBurned: <LocalQuantitySample>[],
    basalEnergyBurned: <LocalQuantitySample>[],
    steps: <LocalQuantitySample>[],
    floorsClimbed: <LocalQuantitySample>[],
    vo2Max: <LocalQuantitySample>[],
  );
}

SyncStatus mapArgumentsToStatus(List<dynamic> arguments) {
  switch (arguments[0] as String) {
    case 'failedSyncing':
      return SyncStatusFailed(
          HealthResource.values.firstWhere((it) => it.name == arguments[1]),
          arguments[2]);
    case 'successSyncing':
      final resource =
          HealthResource.values.firstWhere((it) => it.name == arguments[1]);
      return SyncStatusSuccessSyncing(
        resource,
        fromArgument(resource, arguments[2]),
      );
    case 'nothingToSync':
      return SyncStatusNothingToSync(
          HealthResource.values.firstWhere((it) => it.name == arguments[1]));
    case 'syncing':
      return SyncStatusSyncing(
          HealthResource.values.firstWhere((it) => it.name == arguments[1]));
    case 'syncingCompleted':
      return SyncStatusCompleted();
    default:
      return SyncStatusUnknown();
  }
}

LocalBloodPressureSample? _bloodPressureSampleFromJson(e) {
  try {
    return LocalBloodPressureSample(
      systolic: _sampleFromJson(e["systolic"])!,
      diastolic: _sampleFromJson(e["diastolic"])!,
      pulse: e["pulse"] != null ? _sampleFromJson(e["pulse"]) : null,
    );
  } catch (e, stacktrace) {
    Fimber.i("Error parsing sample: $e $stacktrace");
    return null;
  }
}

LocalQuantitySample? _sampleFromJson(Map<dynamic, dynamic> json) {
  try {
    return LocalQuantitySample(
      id: json['id'] as String?,
      value: (json['value'] as num).toDouble(),
      unit: json['unit'] as String,
      startDate: DateTime.fromMillisecondsSinceEpoch(
          (json['startDate'] as num).toInt(),
          isUtc: true),
      endDate: DateTime.fromMillisecondsSinceEpoch(
          (json['endDate'] as num).toInt(),
          isUtc: true),
      type: json['type'] as String?,
    );
  } catch (e, stacktrace) {
    Fimber.i("Error parsing sample: $e $stacktrace");
    return null;
  }
}

VitalException _mapException(Exception e) {
  if (e is PlatformException) {
    switch (e.code) {
      case "ClientSetup":
        return ClientSetupException(e.message ?? "");
      case "UnsupportedRegion":
        return UnsupportedRegionException(e.message ?? "");
      case "UnsupportedEnvironment":
        return UnsupportedEnvironmentException(e.message ?? "");
      case "UnsupportedResource":
        return UnsupportedResourceException(e.message ?? "");
      case "UnsupportedDataPushMode":
        return UnsupportedDataPushModeException(e.message ?? "");
      case "UnsupportedProvider":
        return UnsupportedProviderException(e.message ?? "");
      default:
        return UnknownException(e.message ?? "");
    }
  } else {
    return UnknownException(e.toString());
  }
}
