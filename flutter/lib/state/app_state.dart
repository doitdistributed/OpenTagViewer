import 'package:flutter/foundation.dart';

import '../models/apple_user_data.dart';
import '../models/beacon_information.dart';
import '../models/beacon_location_report.dart';
import '../services/apple_auth_service.dart';
import '../services/anisette_service.dart' show AnisetteService;
import '../services/beacon_report_service.dart';

/// Sentinel indicating that no change should be made to a beacon override.
const _keepOverride = Object();

/// Application-wide state provider.
///
/// Holds authentication state, the list of imported beacons, and their
/// most recently fetched location reports.
class AppState extends ChangeNotifier {
  final AppleAuthService _authService;
  final BeaconReportService _reportService;

  /// Exposed so that screens can reuse the configured service instance
  /// rather than creating new instances with independent storage backends.
  AppleAuthService get authService => _authService;

  /// Exposed so that screens can reuse the configured service instance.
  BeaconReportService get beaconReportService => _reportService;

  AppState({
    AppleAuthService? authService,
    BeaconReportService? reportService,
  })  : _authService = authService ?? AppleAuthService(),
        _reportService = reportService ?? BeaconReportService();

  // ---- Auth ----------------------------------------------------------------

  AppleUserData? _currentUser;
  AppleUserData? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;

  String _anisetteServerUrl = AnisetteService.defaultAnisetteUrl;
  String get anisetteServerUrl => _anisetteServerUrl;

  /// Loads any persisted session from secure storage.
  Future<void> init() async {
    _currentUser = await _authService.getStoredUser();
    notifyListeners();
  }

  void setAnisetteServerUrl(String url) {
    _anisetteServerUrl = url;
    notifyListeners();
  }

  void setUser(AppleUserData user) {
    _currentUser = user;
    notifyListeners();
  }

  Future<void> logout() async {
    await _authService.logout();
    _currentUser = null;
    _beacons.clear();
    _latestReports.clear();
    _latestReportCache.clear();
    notifyListeners();
  }

  // ---- Beacons -------------------------------------------------------------

  final List<BeaconInformation> _beacons = [];
  List<BeaconInformation> get beacons => List.unmodifiable(_beacons);

  void setBeacons(List<BeaconInformation> beacons) {
    _beacons
      ..clear()
      ..addAll(beacons);
    notifyListeners();
  }

  /// Updates the display name and/or emoji override for a beacon.
  ///
  /// Pass `null` to explicitly clear an override and revert to the
  /// original value stored in the plist, or omit the parameter to
  /// leave the current value unchanged.
  void updateBeaconOverrides(
      String beaconId, {
      Object? name = _keepOverride,
      Object? emoji = _keepOverride,
  }) {
    final idx = _beacons.indexWhere((b) => b.beaconId == beaconId);
    if (idx < 0) return;
    final updated = _beacons[idx].copyWith(
      userOverrideName: identical(name, _keepOverride) ? _keepOverride : name,
      userOverrideEmoji:
          identical(emoji, _keepOverride) ? _keepOverride : emoji,
    );
    _beacons[idx] = updated;
    notifyListeners();
  }

  void removeBeacon(String beaconId) {
    _beacons.removeWhere((b) => b.beaconId == beaconId);
    _latestReports.remove(beaconId);
    _latestReportCache.remove(beaconId);
    notifyListeners();
  }

  // ---- Location reports ----------------------------------------------------

  final Map<String, List<BeaconLocationReport>> _latestReports = {};

  /// Cached per-beacon latest report for O(1) lookups.
  final Map<String, BeaconLocationReport> _latestReportCache = {};

  Map<String, List<BeaconLocationReport>> get latestReports =>
      Map.unmodifiable(_latestReports);

  bool _isLoadingReports = false;
  bool get isLoadingReports => _isLoadingReports;

  String? _reportsError;
  String? get reportsError => _reportsError;

  /// Fetches the latest location reports for all imported beacons.
  Future<void> refreshReports({int hoursBack = 24}) async {
    final user = _currentUser;
    if (user == null || _beacons.isEmpty) return;

    _isLoadingReports = true;
    _reportsError = null;
    notifyListeners();

    try {
      final idToPList = {
        for (final b in _beacons)
          if (b.ownedBeaconPlistRaw != null)
            b.beaconId: b.ownedBeaconPlistRaw!,
      };

      final reports = await _reportService.getLastReports(
        accountToken: user.accountToken,
        beaconIdToPList: idToPList,
        anisetteServerUrl: _anisetteServerUrl,
        hoursBack: hoursBack,
      );

      _latestReports
        ..clear()
        ..addAll(reports);

      // Cache the latest (highest-timestamp) report per beacon so that
      // latestReportFor() is O(1) after the fetch.
      _latestReportCache.clear();
      for (final entry in _latestReports.entries) {
        if (entry.value.isEmpty) continue;
        _latestReportCache[entry.key] = entry.value
            .reduce((a, b) => a.timestamp > b.timestamp ? a : b);
      }
    } catch (e) {
      _reportsError = e.toString();
    } finally {
      _isLoadingReports = false;
      notifyListeners();
    }
  }

  BeaconLocationReport? latestReportFor(String beaconId) =>
      _latestReportCache[beaconId];
}
