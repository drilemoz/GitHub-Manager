import 'package:flutter/services.dart';


class AndroidDeviceInfo {
  const AndroidDeviceInfo({
    required this.manufacturer,
    required this.model,
    required this.androidRelease,
    required this.sdkInt,
    required this.supportedAbis,
    required this.supported64BitAbis,
  });

  final String manufacturer;
  final String model;
  final String androidRelease;
  final int sdkInt;
  final List<String> supportedAbis;
  final List<String> supported64BitAbis;

  String get primaryAbi => supportedAbis.isEmpty ? 'desconhecida' : supportedAbis.first;
  bool get supports64Bit => supported64BitAbis.isNotEmpty;

  factory AndroidDeviceInfo.fromMap(Map<String, Object?> map) => AndroidDeviceInfo(
        manufacturer: map['manufacturer']?.toString() ?? '',
        model: map['model']?.toString() ?? 'Android',
        androidRelease: map['androidRelease']?.toString() ?? '-',
        sdkInt: (map['sdkInt'] as num?)?.toInt() ?? 0,
        supportedAbis: (map['supportedAbis'] as List?)
                ?.map((value) => value.toString())
                .where((value) => value.isNotEmpty)
                .toList(growable: false) ??
            const <String>[],
        supported64BitAbis: (map['supported64BitAbis'] as List?)
                ?.map((value) => value.toString())
                .where((value) => value.isNotEmpty)
                .toList(growable: false) ??
            const <String>[],
      );
}

enum InstalledAppQueryStatus { installed, notInstalled, unknown }

class InstalledAndroidApp {
  const InstalledAndroidApp({
    required this.status,
    this.packageName,
    this.versionName,
    this.versionCode,
    this.reason,
  });

  final InstalledAppQueryStatus status;
  final String? packageName;
  final String? versionName;
  final int? versionCode;
  final String? reason;

  factory InstalledAndroidApp.fromMap(Map<String, Object?> data) =>
      InstalledAndroidApp(
        status: switch (data['status']) {
          'installed' => InstalledAppQueryStatus.installed,
          'notInstalled' => InstalledAppQueryStatus.notInstalled,
          _ => InstalledAppQueryStatus.unknown,
        },
        packageName: data['packageName'] as String?,
        versionName: data['versionName'] as String?,
        versionCode: (data['versionCode'] as num?)?.toInt(),
        reason: data['reason'] as String?,
      );
}

class ActivityLaunchState {
  const ActivityLaunchState({
    required this.cachedEngineReattach,
    required this.flutterUiDisplayed,
    required this.taskId,
    required this.restoredActivityState,
  });

  final bool cachedEngineReattach;
  final bool flutterUiDisplayed;
  final int? taskId;
  final bool restoredActivityState;

  factory ActivityLaunchState.fromMap(Map<String, Object?> map) {
    return ActivityLaunchState(
      cachedEngineReattach: map['cachedEngineReattach'] == true,
      flutterUiDisplayed: map['flutterUiDisplayed'] == true,
      taskId: (map['taskId'] as num?)?.toInt(),
      restoredActivityState: map['restoredActivityState'] == true,
    );
  }

  Map<String, Object?> toTelemetryContext() => {
        'cachedEngineReattach': cachedEngineReattach,
        'flutterUiDisplayed': flutterUiDisplayed,
        if (taskId != null) 'taskId': taskId,
        'restoredActivityState': restoredActivityState,
      };
}

abstract final class PlatformActions {
  static const _channel = MethodChannel('br.com.githubmanager.app/platform');

  static Future<void> openUri(String uri, {String? mimeType}) async {
    final arguments = <String, dynamic>{'uri': uri};
    if (mimeType != null) {
      arguments['mimeType'] = mimeType;
    }
    await _channel.invokeMethod<void>('openUri', arguments);
  }

  static Future<void> openFile(String location, {String? mimeType}) async {
    final arguments = <String, dynamic>{'path': location};
    if (mimeType != null) {
      arguments['mimeType'] = mimeType;
    }
    await _channel.invokeMethod<void>('openFile', arguments);
  }

  static Future<String?> installApk(String location) =>
      _channel.invokeMethod<String>('installApk', {'path': location});

  static Future<void> shareFile(String location, {String? mimeType}) async {
    final arguments = <String, dynamic>{'path': location};
    if (mimeType != null) {
      arguments['mimeType'] = mimeType;
    }
    await _channel.invokeMethod<void>('shareFile', arguments);
  }

  static Future<String> publishToDownloads({
    required String sourcePath,
    required String fileName,
    required String mimeType,
    String? relativeFolder,
  }) async {
    final location = await _channel.invokeMethod<String>(
      'publishToDownloads',
      {
        'sourcePath': sourcePath,
        'fileName': fileName,
        'mimeType': mimeType,
        'relativeFolder': relativeFolder,
      },
    );
    if (location == null || location.isEmpty) {
      throw PlatformException(
        code: 'DOWNLOAD_PUBLISH_FAILED',
        message: 'O Android não retornou o arquivo publicado.',
      );
    }
    return location;
  }

  static Future<bool> requestLegacyDownloadsPermission() async =>
      await _channel.invokeMethod<bool>('requestLegacyDownloadsPermission') ??
      false;

  static Future<bool> deletePublishedDownload(String location) async =>
      await _channel.invokeMethod<bool>('deletePublishedDownload', {
        'location': location,
      }) ??
      false;

  /// Remove arquivos finais de propriedade do app, na pasta exata do projeto.
  /// Não percorre pastas de usuários nem alcança arquivos .part.
  static Future<Map<String, dynamic>> cleanupManagedProjectDownloads({
    required String relativeFolder,
    String? keepLocation,
  }) async {
    final response = await _channel.invokeMapMethod<String, dynamic>(
      'cleanupManagedProjectDownloads',
      {'relativeFolder': relativeFolder, 'keepLocation': keepLocation},
    );
    if (response == null) {
      throw PlatformException(
        code: 'DOWNLOAD_CLEANUP_NOT_CONFIRMED',
        message: 'O Android não confirmou a limpeza dos downloads.',
      );
    }
    return response;
  }

  static Future<void> showUploadForegroundService({
    required bool startService,
    required String uploadId,
    required String projectName,
    required String repositoryFullName,
    required String phase,
    required int current,
    required int total,
    required bool indeterminate,
    required int activeCount,
  }) =>
      _channel.invokeMethod<void>('showUploadForegroundService', {
        'startService': startService,
        'uploadId': uploadId,
        'projectName': projectName,
        'repositoryFullName': repositoryFullName,
        'phase': phase,
        'current': current,
        'total': total,
        'indeterminate': indeterminate,
        'activeCount': activeCount,
      });

  static Future<void> stopUploadForegroundService() =>
      _channel.invokeMethod<void>('stopUploadForegroundService');

  static Future<void> showDownloadForegroundService({
    required bool startService,
    required String downloadId,
    required String fileName,
    required String repositoryFullName,
    required int current,
    required int total,
    required bool indeterminate,
    required int activeCount,
  }) =>
      _channel.invokeMethod<void>('showDownloadForegroundService', {
        'startService': startService,
        'downloadId': downloadId,
        'fileName': fileName,
        'repositoryFullName': repositoryFullName,
        'current': current,
        'total': total,
        'indeterminate': indeterminate,
        'activeCount': activeCount,
      });

  static Future<void> stopDownloadForegroundService() =>
      _channel.invokeMethod<void>('stopDownloadForegroundService');

  static Future<String?> consumeNativeCrashReport() =>
      _channel.invokeMethod<String>('consumeNativeCrashReport');

  static Future<String?> consumeNativeEngineLifecycleReport() =>
      _channel.invokeMethod<String>('consumeNativeEngineLifecycleReport');

  /// Cancela apenas canais de avisos opcionais, preservando notificações
  /// foreground de uploads/downloads ativos que mantêm seus serviços vivos.
  static Future<void> clearOptionalNotifications() =>
      _channel.invokeMethod<void>('clearOptionalNotifications');

  static Future<AndroidDeviceInfo> getAndroidDeviceInfo() async {
    final raw = await _channel.invokeMapMethod<String, Object?>('getDeviceInfo');
    if (raw == null) {
      throw PlatformException(
        code: 'DEVICE_INFO_UNAVAILABLE',
        message: 'O Android não retornou as informações do aparelho.',
      );
    }
    return AndroidDeviceInfo.fromMap(raw);
  }

  static Future<InstalledAndroidApp> getInstalledAppInfo(
    String packageName,
  ) async {
    final raw = await _channel.invokeMapMethod<String, Object?>(
      'getInstalledAppInfo',
      {'packageName': packageName},
    );
    if (raw == null) {
      return const InstalledAndroidApp(status: InstalledAppQueryStatus.unknown);
    }
    return InstalledAndroidApp.fromMap(raw);
  }

  static Future<ActivityLaunchState> getActivityLaunchState() async {
    final raw = await _channel.invokeMapMethod<String, Object?>(
      'getActivityLaunchState',
    );
    if (raw == null) {
      throw PlatformException(
        code: 'ACTIVITY_STATE_UNAVAILABLE',
        message: 'O Android não retornou o estado atual da Activity.',
      );
    }
    return ActivityLaunchState.fromMap(raw);
  }
}
