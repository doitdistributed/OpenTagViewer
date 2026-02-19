import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/beacon_location_report.dart';

/// Thrown when fetching location reports fails.
class BeaconReportException implements Exception {
  final String message;
  const BeaconReportException(this.message);

  @override
  String toString() => 'BeaconReportException: $message';
}

/// Fetches AirTag location reports from Apple's FindMy network via the
/// Anisette-backed backend.
///
/// This service mirrors the functionality of [PythonAppleService] in the
/// Android app.
class BeaconReportService {
  final http.Client _client;

  BeaconReportService({http.Client? client})
      : _client = client ?? http.Client();

  /// Returns the most recent location reports for the given beacons.
  ///
  /// [accountToken] is the opaque token obtained during login.
  /// [beaconIdToPList] maps each beacon UUID to its raw .plist XML string.
  /// [hoursBack] controls how far back in time to look (default: 24 hours).
  /// [anisetteServerUrl] is the base URL of the Anisette server.
  Future<Map<String, List<BeaconLocationReport>>> getLastReports({
    required String accountToken,
    required Map<String, String> beaconIdToPList,
    required String anisetteServerUrl,
    int hoursBack = 24,
  }) async {
    if (beaconIdToPList.isEmpty) return {};

    final uri = Uri.parse('$anisetteServerUrl/reports/last');
    final response = await _client.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accountToken',
      },
      body: jsonEncode({
        'beacons': beaconIdToPList.entries
            .map((e) => {'id': e.key, 'plist': e.value})
            .toList(),
        'hoursBack': hoursBack,
      }),
    );

    if (response.statusCode != 200) {
      throw BeaconReportException(
          'Failed to fetch location reports (HTTP ${response.statusCode})');
    }

    return _parseReportsResponse(response.body);
  }

  /// Returns location reports between two UNIX timestamps (milliseconds).
  Future<Map<String, List<BeaconLocationReport>>> getReportsBetween({
    required String accountToken,
    required Map<String, String> beaconIdToPList,
    required String anisetteServerUrl,
    required int startTimeMs,
    required int endTimeMs,
  }) async {
    if (beaconIdToPList.isEmpty) return {};

    final uri = Uri.parse('$anisetteServerUrl/reports/between');
    final response = await _client.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accountToken',
      },
      body: jsonEncode({
        'beacons': beaconIdToPList.entries
            .map((e) => {'id': e.key, 'plist': e.value})
            .toList(),
        'startTimeMs': startTimeMs,
        'endTimeMs': endTimeMs,
      }),
    );

    if (response.statusCode != 200) {
      throw BeaconReportException(
          'Failed to fetch location reports (HTTP ${response.statusCode})');
    }

    return _parseReportsResponse(response.body);
  }

  // ---------------------------------------------------------------------------

  Map<String, List<BeaconLocationReport>> _parseReportsResponse(String body) {
    final data = jsonDecode(body) as Map<String, dynamic>;
    final result = <String, List<BeaconLocationReport>>{};

    for (final entry in data.entries) {
      final beaconId = entry.key;
      final rawReports = entry.value as List<dynamic>;
      result[beaconId] = rawReports.map((r) {
        final map = r as Map<String, dynamic>;
        return BeaconLocationReport(
          publishedAt: (map['publishedAt'] as num).toInt(),
          description: map['description'] as String?,
          timestamp: (map['timestamp'] as num).toInt(),
          confidence: (map['confidence'] as num?)?.toInt() ?? 1,
          latitude: (map['latitude'] as num).toDouble(),
          longitude: (map['longitude'] as num).toDouble(),
          horizontalAccuracy: (map['horizontalAccuracy'] as num?)?.toInt() ?? 0,
          status: (map['status'] as num?)?.toInt() ?? 0,
        );
      }).toList();
    }

    return result;
  }
}
