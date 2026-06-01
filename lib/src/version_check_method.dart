/// Defines how version comparison should be performed
enum VersionCheckMethod {
  /// Check version name first, then build number if versions are equal
  versionFirstThenBuild,

  /// Check build number first, then version name if build numbers are equal
  buildFirstThenVersion,

  /// Only check build number, ignore version name
  buildNumberOnly,

  /// Only check version name, ignore build number
  versionNameOnly,
}
