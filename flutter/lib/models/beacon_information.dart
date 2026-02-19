/// Represents the information about a tracked beacon (e.g. an AirTag or other
/// FindMy-compatible accessory).
///
/// Mirrors the Java [BeaconInformation] model from the Android app.
class BeaconInformation {
  static const String _ipad = 'iPad';
  static const int _airTagProductId = 21760;

  final String beaconId;
  final String? namingRecordId;

  /// Emoji configured for this beacon (set via Apple devices).
  final String? originalEmoji;

  /// Name configured for this beacon (set via Apple devices).
  final String? originalName;

  final int? namingRecordCreationTime;
  final int? namingRecordModifiedTime;
  final String? namingRecordModifiedByDevice;

  /// Raw string contents of the decoded .plist XML file for this beacon.
  final String? ownedBeaconPlistRaw;

  /// 0 or 1 battery level indicator.
  final int batteryLevel;

  /// Device model identifier (e.g. "iPad13,18"). May be empty for AirTags.
  final String? model;

  /// ISO 8601 pairing date.
  final String? pairingDate;

  /// Product identifier. AirTags have productId == 21760.
  final int productId;

  final List<String> stableIdentifier;

  /// Firmware/OS version string.
  final String? systemVersion;

  /// Bluetooth manufacturer vendor id. AirTags have vendorId == 76 (0x4C).
  final int vendorId;

  /// User-provided override for the display name (replaces [originalName]).
  String? userOverrideName;

  /// User-provided override for the display emoji (replaces [originalEmoji]).
  String? userOverrideEmoji;

  BeaconInformation({
    required this.beaconId,
    this.namingRecordId,
    this.originalEmoji,
    this.originalName,
    this.namingRecordCreationTime,
    this.namingRecordModifiedTime,
    this.namingRecordModifiedByDevice,
    this.ownedBeaconPlistRaw,
    this.batteryLevel = 0,
    this.model,
    this.pairingDate,
    this.productId = -1,
    this.stableIdentifier = const [],
    this.systemVersion,
    this.vendorId = -1,
    this.userOverrideName,
    this.userOverrideEmoji,
  });

  /// The display name – user override takes precedence over the original name.
  String? get name => userOverrideName ?? originalName;

  /// The display emoji – user override takes precedence over the original emoji.
  String? get emoji => userOverrideEmoji ?? originalEmoji;

  bool get isEmojiFilled {
    final e = emoji;
    return e != null && e.trim().isNotEmpty;
  }

  bool get isIpad => model?.contains(_ipad) ?? false;

  bool get isAirTag => productId == _airTagProductId;

  BeaconInformation copyWith({
    String? userOverrideName,
    String? userOverrideEmoji,
  }) {
    return BeaconInformation(
      beaconId: beaconId,
      namingRecordId: namingRecordId,
      originalEmoji: originalEmoji,
      originalName: originalName,
      namingRecordCreationTime: namingRecordCreationTime,
      namingRecordModifiedTime: namingRecordModifiedTime,
      namingRecordModifiedByDevice: namingRecordModifiedByDevice,
      ownedBeaconPlistRaw: ownedBeaconPlistRaw,
      batteryLevel: batteryLevel,
      model: model,
      pairingDate: pairingDate,
      productId: productId,
      stableIdentifier: stableIdentifier,
      systemVersion: systemVersion,
      vendorId: vendorId,
      userOverrideName: userOverrideName ?? this.userOverrideName,
      userOverrideEmoji: userOverrideEmoji ?? this.userOverrideEmoji,
    );
  }

  @override
  String toString() => 'BeaconInformation(beaconId: $beaconId, name: $name)';
}
