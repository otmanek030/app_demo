class VersionModel {
  final String versionName;
  final int versionCode;
  final String releaseNotes;
  final String updateType;
  final int gracePeriod;
  final String apkUrl;

  VersionModel({
    required this.versionName,
    required this.versionCode,
    required this.releaseNotes,
    required this.updateType,
    required this.gracePeriod,
    required this.apkUrl,
  });

  factory VersionModel.fromJson(Map<String, dynamic> json) {
    return VersionModel(
      versionName: json['version_name'],
      versionCode: json['version_code'],
      releaseNotes: json['release_notes'] ?? '',
      updateType: json['update_type'],
      gracePeriod: json['grace_period'] ?? 0,
      apkUrl: json['apk_url'] ?? '',
    );
  }
}