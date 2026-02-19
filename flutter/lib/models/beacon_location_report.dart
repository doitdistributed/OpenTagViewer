/// Represents a single location report for a beacon.
///
/// Mirrors the Java [BeaconLocationReport] model from the Android app, which
/// in turn mirrors the Python [LocationReport] class from [FindMy.py](https://github.com/malmeloo/FindMy.py).
class BeaconLocationReport {
  /// UNIX timestamp (milliseconds) when this report was published by a device.
  final int publishedAt;

  /// Human-readable description of the location report as published by Apple.
  final String? description;

  /// UNIX timestamp (milliseconds) when this report was recorded by a device.
  final int timestamp;

  /// Confidence of the location – integer between 1 and 3.
  final int confidence;

  /// Latitude of the reported location.
  final double latitude;

  /// Longitude of the reported location.
  final double longitude;

  /// Horizontal accuracy (metres) of the reported location.
  final int horizontalAccuracy;

  /// Status byte of the accessory as an integer.
  final int status;

  const BeaconLocationReport({
    required this.publishedAt,
    this.description,
    required this.timestamp,
    this.confidence = 1,
    required this.latitude,
    required this.longitude,
    this.horizontalAccuracy = 0,
    this.status = 0,
  });

  /// Returns the report timestamp as a [DateTime].
  DateTime get dateTime =>
      DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true).toLocal();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BeaconLocationReport &&
          runtimeType == other.runtimeType &&
          publishedAt == other.publishedAt &&
          timestamp == other.timestamp &&
          latitude == other.latitude &&
          longitude == other.longitude;

  @override
  int get hashCode =>
      publishedAt.hashCode ^
      timestamp.hashCode ^
      latitude.hashCode ^
      longitude.hashCode;

  @override
  String toString() =>
      'BeaconLocationReport(lat: $latitude, lon: $longitude, timestamp: $timestamp)';
}
