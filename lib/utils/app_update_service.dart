import 'dart:ffi';

import 'package:dio/dio.dart';

enum AndroidReleaseAbi { arm64, armv7, x86_64 }

AndroidReleaseAbi currentAndroidReleaseAbi() => switch (Abi.current()) {
  Abi.androidArm => AndroidReleaseAbi.armv7,
  Abi.androidX64 || Abi.androidIA32 => AndroidReleaseAbi.x86_64,
  _ => AndroidReleaseAbi.arm64,
};

class AppReleaseAsset {
  const AppReleaseAsset({
    required this.name,
    required this.downloadUri,
    required this.size,
  });

  final String name;
  final Uri downloadUri;
  final int size;
}

class AppRelease {
  const AppRelease({
    required this.tagName,
    required this.version,
    required this.releasePage,
    required this.assets,
  });

  factory AppRelease.fromJson(Map<String, dynamic> json) {
    final tagName = json['tag_name']?.toString().trim() ?? '';
    final page = Uri.tryParse(json['html_url']?.toString() ?? '');
    if (tagName.isEmpty || page == null || page.scheme != 'https') {
      throw const FormatException('GitHub 发行信息不完整');
    }
    final assets = <AppReleaseAsset>[];
    final rawAssets = json['assets'];
    if (rawAssets is List) {
      for (final raw in rawAssets.whereType<Map>()) {
        final name = raw['name']?.toString().trim() ?? '';
        final uri = Uri.tryParse(raw['browser_download_url']?.toString() ?? '');
        if (name.isEmpty || uri == null || uri.scheme != 'https') continue;
        assets.add(
          AppReleaseAsset(
            name: name,
            downloadUri: uri,
            size: int.tryParse(raw['size']?.toString() ?? '') ?? 0,
          ),
        );
      }
    }
    return AppRelease(
      tagName: tagName,
      version: tagName.replaceFirst(RegExp(r'^[vV]'), ''),
      releasePage: page,
      assets: List.unmodifiable(assets),
    );
  }

  final String tagName;
  final String version;
  final Uri releasePage;
  final List<AppReleaseAsset> assets;

  AppReleaseAsset? apkFor(AndroidReleaseAbi abi) {
    final marker = switch (abi) {
      AndroidReleaseAbi.arm64 => 'arm64-v8a',
      AndroidReleaseAbi.armv7 => 'armeabi-v7a',
      AndroidReleaseAbi.x86_64 => 'x86_64',
    };
    final apkAssets = assets.where(
      (asset) => asset.name.toLowerCase().endsWith('.apk'),
    );
    for (final asset in apkAssets) {
      if (asset.name.toLowerCase().contains(marker)) return asset;
    }
    return apkAssets.firstOrNull;
  }
}

class AppUpdateService {
  AppUpdateService({
    Dio? client,
    this.cacheDuration = const Duration(minutes: 10),
  }) : _client =
           client ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 8),
               receiveTimeout: const Duration(seconds: 15),
               headers: const {
                 'Accept': 'application/vnd.github+json',
                 'X-GitHub-Api-Version': '2026-03-10',
               },
             ),
           );

  static final latestReleaseApi = Uri.parse(
    'https://api.github.com/repos/chin9933/cloudreve-android/releases/latest',
  );
  static final releasesPage = Uri.parse(
    'https://github.com/chin9933/cloudreve-android/releases/latest',
  );

  final Dio _client;
  final Duration cacheDuration;
  AppRelease? _cached;
  DateTime? _cachedAt;

  Future<AppRelease> latest({bool forceRefresh = false}) async {
    final now = DateTime.now();
    if (!forceRefresh &&
        _cached != null &&
        _cachedAt != null &&
        now.difference(_cachedAt!) < cacheDuration) {
      return _cached!;
    }
    final response = await _client.getUri<Object?>(latestReleaseApi);
    final data = response.data;
    if (data is! Map) throw const FormatException('GitHub 返回了无效发行信息');
    final release = AppRelease.fromJson(Map<String, dynamic>.from(data));
    _cached = release;
    _cachedAt = now;
    return release;
  }

  static bool isNewer(String latest, String current) =>
      compareVersions(latest, current) > 0;

  static int compareVersions(String left, String right) {
    final a = _ParsedVersion(left);
    final b = _ParsedVersion(right);
    final count = a.core.length > b.core.length ? a.core.length : b.core.length;
    for (var index = 0; index < count; index++) {
      final l = index < a.core.length ? a.core[index] : 0;
      final r = index < b.core.length ? b.core[index] : 0;
      if (l != r) return l.compareTo(r);
    }
    if (a.preRelease.isEmpty && b.preRelease.isNotEmpty) return 1;
    if (a.preRelease.isNotEmpty && b.preRelease.isEmpty) return -1;
    return a.preRelease.compareTo(b.preRelease);
  }
}

class _ParsedVersion {
  _ParsedVersion(String input)
    : core = _parseCore(input),
      preRelease = _parsePreRelease(input);

  final List<int> core;
  final String preRelease;

  static String _normalized(String input) =>
      input.trim().replaceFirst(RegExp(r'^[vV]'), '').split('+').first;

  static List<int> _parseCore(String input) {
    final value = _normalized(input).split('-').first;
    return value
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList(growable: false);
  }

  static String _parsePreRelease(String input) {
    final value = _normalized(input);
    final separator = value.indexOf('-');
    return separator < 0 ? '' : value.substring(separator + 1);
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
