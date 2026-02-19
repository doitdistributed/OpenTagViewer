import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../models/beacon_location_report.dart';

/// Thrown when fetching location reports fails.
class BeaconReportException implements Exception {
  final String message;
  const BeaconReportException(this.message);

  @override
  String toString() => 'BeaconReportException: $message';
}

/// Validates that [url] uses HTTPS. Throws [BeaconReportException] if it does not.
///
/// All report endpoints transmit the Apple account token and beacon private-key
/// plists, so cleartext HTTP connections must be rejected to prevent credential
/// and tracking-data interception by on-path attackers.
void _requireHttps(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https') {
    throw BeaconReportException(
        'Anisette server URL must use HTTPS to protect your account token '
        'and beacon data. Received: $url');
  }
}

/// Builds a detailed error message from an HTTP [response].
///
/// Includes the status code and up to 200 characters of the response body to
/// aid debugging, without flooding logs with excessively large bodies.
String _httpErrorMessage(String context, http.Response response) {
  final snippet = response.body.substring(0, min(200, response.body.length));
  final body = snippet.isNotEmpty ? ': $snippet' : '';
  return '$context (HTTP ${response.statusCode})$body';
}

/// Fetches AirTag location reports from Apple's FindMy network via the
/// Anisette-backed backend.
///
/// This service mirrors the functionality of [PythonAppleService] in the
/// Android app.
///
/// > **Security note:** all methods reject non-HTTPS Anisette server URLs
/// > to prevent cleartext transmission of account tokens and beacon private
/// > keys.
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
  ///
  /// Throws [BeaconReportException] if [anisetteServerUrl] is not HTTPS.
  Future<Map<String, List<BeaconLocationReport>>> getLastReports({
    required String accountToken,
    required Map<String, String> beaconIdToPList,
    required String anisetteServerUrl,
    int hoursBack = 24,
  }) async {
    if (beaconIdToPList.isEmpty) return {};

    _requireHttps(anisetteServerUrl);

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
          _httpErrorMessage('Failed to fetch location reports', response));
    }

    return _parseReportsResponse(response.body);
  }

  /// Returns location reports between two UNIX timestamps (milliseconds).
  ///
  /// Throws [BeaconReportException] if [anisetteServerUrl] is not HTTPS.
  Future<Map<String, List<BeaconLocationReport>>> getReportsBetween({
    required String accountToken,
    required Map<String, String> beaconIdToPList,
    required String anisetteServerUrl,
    required int startTimeMs,
    required int endTimeMs,
  }) async {
    if (beaconIdToPList.isEmpty) return {};

    _requireHttps(anisetteServerUrl);

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
          _httpErrorMessage('Failed to fetch location reports', response));
    }

    return _parseReportsResponse(response.body);
  }

  // ---------------------------------------------------------------------------

  Map<String, List<BeaconLocationReport>> _parseReportsResponse(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const BeaconReportException(
            'Malformed reports response: root is not a JSON object');
      }

      final result = <String, List<BeaconLocationReport>>{};

      for (final entry in decoded.entries) {
        final beaconId = entry.key;
        final rawReports = entry.value;

        if (rawReports is! List) {
          throw BeaconReportException(
              'Malformed reports response: expected a list of reports for '
              'beacon $beaconId');
        }

        result[beaconId] = rawReports.map<BeaconLocationReport>((r) {
          if (r is! Map<String, dynamic>) {
            throw const BeaconReportException(
                'Malformed reports response: each report must be a JSON object');
          }
          return BeaconLocationReport(
            publishedAt: (r['publishedAt'] as num).toInt(),
            description: r['description'] as String?,
            timestamp: (r['timestamp'] as num).toInt(),
            confidence: (r['confidence'] as num?)?.toInt() ?? 1,
            latitude: (r['latitude'] as num).toDouble(),
            longitude: (r['longitude'] as num).toDouble(),
            horizontalAccuracy:
                (r['horizontalAccuracy'] as num?)?.toInt() ?? 0,
            status: (r['status'] as num?)?.toInt() ?? 0,
          );
        }).toList();
      }

      return result;
    } on BeaconReportException {
      rethrow;
    } catch (e) {
      throw BeaconReportException('Malformed reports response: $e');
    }
  }
}
