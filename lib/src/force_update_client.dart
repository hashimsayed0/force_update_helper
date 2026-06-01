import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';

import 'version_check_method.dart';

/// Client used to check if a force upgrade is needed
class ForceUpdateClient {
  ForceUpdateClient({
    required this.fetchRequiredVersion,
    required this.iosAppStoreId,
    this.versionCheckMethod = VersionCheckMethod.versionFirstThenBuild,
    this.currentVersionName,
    this.currentBuildNumber,
    this.currentVersion,
  }) {
    _validateVersionInput();
  }

  /// Fetches the required version from remote source
  /// Can return either:
  /// - Combined format: '1.8.11+154'
  /// - Version name only: '1.8.11'
  /// - Build number only: '154'
  final Future<String> Function() fetchRequiredVersion;

  final String iosAppStoreId;

  /// Defines which version check method to use
  final VersionCheckMethod versionCheckMethod;

  /// Current app version name (e.g., '1.8.11')
  /// Optional if currentVersion is provided
  final String? currentVersionName;

  /// Current app build number (e.g., '154')
  /// Optional if currentVersion is provided
  final String? currentBuildNumber;

  /// Current app version in combined format (e.g., '1.8.11+154')
  /// Optional if currentVersionName and currentBuildNumber are provided
  final String? currentVersion;

  static const _name = 'Force Update';

  void _validateVersionInput() {
    final hasCombined = currentVersion != null && currentVersion!.isNotEmpty;
    final hasSeparate =
        (currentVersionName != null && currentVersionName!.isNotEmpty) ||
            (currentBuildNumber != null && currentBuildNumber!.isNotEmpty);

    if (!hasCombined && !hasSeparate) {
      // It's okay, we'll use PackageInfo
      // But we should warn if using build/version only methods
      if (versionCheckMethod == VersionCheckMethod.buildNumberOnly ||
          versionCheckMethod == VersionCheckMethod.versionNameOnly) {
        log(
          'Warning: Using ${versionCheckMethod.name} without explicit version parameters. '
          'Will attempt to use PackageInfo. Ensure your pubspec.yaml has the required information.',
          name: _name,
        );
      }
      return;
    }

    // If using separate parameters, validate based on check method
    if (hasSeparate && !hasCombined) {
      switch (versionCheckMethod) {
        case VersionCheckMethod.versionFirstThenBuild:
        case VersionCheckMethod.buildFirstThenVersion:
          if (currentVersionName == null ||
              currentVersionName!.isEmpty ||
              currentBuildNumber == null ||
              currentBuildNumber!.isEmpty) {
            throw ArgumentError(
                'Both currentVersionName and currentBuildNumber are required for ${versionCheckMethod.name}');
          }
          break;
        case VersionCheckMethod.buildNumberOnly:
          if (currentBuildNumber == null || currentBuildNumber!.isEmpty) {
            throw ArgumentError(
                'currentBuildNumber is required for buildNumberOnly method');
          }
          break;
        case VersionCheckMethod.versionNameOnly:
          if (currentVersionName == null || currentVersionName!.isEmpty) {
            throw ArgumentError(
                'currentVersionName is required for versionNameOnly method');
          }
          break;
      }
    }

    // If using combined format, validate it contains required parts
    if (hasCombined && !hasSeparate) {
      switch (versionCheckMethod) {
        case VersionCheckMethod.buildNumberOnly:
          if (!currentVersion!.contains('+')) {
            throw ArgumentError(
                'currentVersion must contain build number (format: "version+build") '
                'when using buildNumberOnly method');
          }
          break;
        case VersionCheckMethod.versionNameOnly:
          // Version name can be with or without build number
          break;
        case VersionCheckMethod.versionFirstThenBuild:
        case VersionCheckMethod.buildFirstThenVersion:
          if (!currentVersion!.contains('+')) {
            log(
              'Warning: currentVersion should contain both version and build (format: "1.0.0+154") '
              'for ${versionCheckMethod.name}. Only version name found.',
              name: _name,
            );
          }
          break;
      }
    }
  }

  /// Parse version string in format '1.8.11+154' or '1.8.11' or '154'
  Map<String, String?> _parseVersionString(String versionStr) {
    if (versionStr.contains('+')) {
      final parts = versionStr.split('+');
      return {
        'versionName': parts[0],
        'buildNumber': parts.length > 1 ? parts[1] : null,
      };
    }

    // Check if it's a version name (contains dots) or build number (numeric only)
    if (versionStr.contains('.')) {
      return {'versionName': versionStr, 'buildNumber': null};
    } else {
      return {'versionName': null, 'buildNumber': versionStr};
    }
  }

  /// Get current version information
  Future<Map<String, String?>> _getCurrentVersionInfo() async {
    // If combined version is provided, parse it
    if (currentVersion != null && currentVersion!.isNotEmpty) {
      return _parseVersionString(currentVersion!);
    }

    // If separate versions are provided, use them
    if (currentVersionName != null || currentBuildNumber != null) {
      return {
        'versionName': currentVersionName,
        'buildNumber': currentBuildNumber,
      };
    }

    // Otherwise, get from PackageInfo
    final packageInfo = await PackageInfo.fromPlatform();
    final versionName =
        RegExp(r'\d+\.\d+\.\d+(?:-[a-zA-Z0-9]+(?:\.[a-zA-Z0-9]+)*)?')
            .matchAsPrefix(packageInfo.version)
            ?.group(0);

    return {
      'versionName': versionName,
      'buildNumber': packageInfo.buildNumber,
    };
  }

  /// Fetches the required version and checks if a force update is needed
  Future<bool> isAppUpdateRequired() async {
    // * Only force app update on iOS & Android
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }

    final requiredVersionStr = await fetchRequiredVersion();
    if (requiredVersionStr.isEmpty) {
      log('Remote Config: required_version not set. Ignoring.', name: _name);
      return false;
    }

    final currentVersionInfo = await _getCurrentVersionInfo();
    final requiredVersionInfo = _parseVersionString(requiredVersionStr);

    final updateRequired = _compareVersions(
      currentVersionInfo,
      requiredVersionInfo,
    );

    log(
      'Update ${updateRequired ? '' : 'not '}required. '
      'Method: ${versionCheckMethod.name}, '
      'Current: v${currentVersionInfo['versionName'] ?? 'N/A'}+${currentVersionInfo['buildNumber'] ?? 'N/A'}, '
      'Required: v${requiredVersionInfo['versionName'] ?? 'N/A'}+${requiredVersionInfo['buildNumber'] ?? 'N/A'}',
      name: _name,
    );

    return updateRequired;
  }

  bool _compareVersions(
    Map<String, String?> current,
    Map<String, String?> required,
  ) {
    switch (versionCheckMethod) {
      case VersionCheckMethod.versionFirstThenBuild:
        return _compareVersionFirstThenBuild(current, required);

      case VersionCheckMethod.buildFirstThenVersion:
        return _compareBuildFirstThenVersion(current, required);

      case VersionCheckMethod.buildNumberOnly:
        return _compareBuildNumberOnly(current, required);

      case VersionCheckMethod.versionNameOnly:
        return _compareVersionNameOnly(current, required);
    }
  }

  bool _compareVersionFirstThenBuild(
    Map<String, String?> current,
    Map<String, String?> required,
  ) {
    final currentVer = current['versionName'];
    final requiredVer = required['versionName'];

    if (currentVer == null || requiredVer == null) {
      log('Version name missing, falling back to build number comparison',
          name: _name);
      return _compareBuildNumberOnly(current, required);
    }

    try {
      final currentVersion = Version.parse(currentVer);
      final requiredVersion = Version.parse(requiredVer);

      // If versions are different, return based on version comparison
      if (currentVersion != requiredVersion) {
        return currentVersion < requiredVersion;
      }

      // If versions are equal, check build number
      return _compareBuildNumberOnly(current, required);
    } catch (e) {
      log('Error parsing version: $e', name: _name);
      return false;
    }
  }

  bool _compareBuildFirstThenVersion(
    Map<String, String?> current,
    Map<String, String?> required,
  ) {
    final currentBuild = current['buildNumber'];
    final requiredBuild = required['buildNumber'];

    if (currentBuild == null || requiredBuild == null) {
      log('Build number missing, falling back to version comparison',
          name: _name);
      return _compareVersionNameOnly(current, required);
    }

    try {
      final currentBuildNum = int.parse(currentBuild);
      final requiredBuildNum = int.parse(requiredBuild);

      // If build numbers are different, return based on build comparison
      if (currentBuildNum != requiredBuildNum) {
        return currentBuildNum < requiredBuildNum;
      }

      // If build numbers are equal, check version name
      return _compareVersionNameOnly(current, required);
    } catch (e) {
      log('Error parsing build number: $e', name: _name);
      return false;
    }
  }

  bool _compareBuildNumberOnly(
    Map<String, String?> current,
    Map<String, String?> required,
  ) {
    final currentBuild = current['buildNumber'];
    final requiredBuild = required['buildNumber'];

    if (currentBuild == null || requiredBuild == null) {
      log('Build number missing for comparison', name: _name);
      return false;
    }

    try {
      final currentBuildNum = int.parse(currentBuild);
      final requiredBuildNum = int.parse(requiredBuild);
      return currentBuildNum < requiredBuildNum;
    } catch (e) {
      log('Error parsing build number: $e', name: _name);
      return false;
    }
  }

  bool _compareVersionNameOnly(
    Map<String, String?> current,
    Map<String, String?> required,
  ) {
    final currentVer = current['versionName'];
    final requiredVer = required['versionName'];

    if (currentVer == null || requiredVer == null) {
      log('Version name missing for comparison', name: _name);
      return false;
    }

    try {
      final currentVersion = Version.parse(currentVer);
      final requiredVersion = Version.parse(requiredVer);
      return currentVersion < requiredVersion;
    } catch (e) {
      log('Error parsing version: $e', name: _name);
      return false;
    }
  }

  /// Returns the download URL for each store depending on the platform
  Future<String?> storeUrl() async {
    if (kIsWeb) {
      return null;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // * On iOS, use the given app ID
      return iosAppStoreId.isNotEmpty
          ? 'https://apps.apple.com/app/id$iosAppStoreId'
          : null;
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      final packageInfo = await PackageInfo.fromPlatform();
      // * On Android, use the package name from PackageInfo
      return 'https://play.google.com/store/apps/details?id=${packageInfo.packageName}';
    } else {
      log('No store URL for platform: ${defaultTargetPlatform.name}',
          name: _name);
      return null;
    }
  }
}
