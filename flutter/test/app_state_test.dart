import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';

import 'package:opentagviewer/models/apple_user_data.dart';
import 'package:opentagviewer/models/beacon_information.dart';
import 'package:opentagviewer/services/apple_auth_service.dart';
import 'package:opentagviewer/services/beacon_report_service.dart';
import 'package:opentagviewer/state/app_state.dart';

/// Helper that builds a [BeaconInformation] suitable for tests.
BeaconInformation _makeBeacon(String id, {String plist = '<plist/>'}) {
  return BeaconInformation(
    beaconId: id,
    originalName: 'Beacon $id',
    ownedBeaconPlistRaw: plist,
  );
}

AppState _makeAppState({http.Client? reportClient}) {
  final authService = AppleAuthService(
    storage: InMemoryCredentialStorage(),
  );
  final reportService =
      reportClient != null ? BeaconReportService(client: reportClient) : null;
  return AppState(
    authService: authService,
    reportService: reportService,
  );
}

void main() {
  group('AppState – beacon management', () {
    test('setBeacons stores beacons and notifies listeners', () {
      final state = _makeAppState();
      var notified = 0;
      state.addListener(() => notified++);

      state.setBeacons([_makeBeacon('b1'), _makeBeacon('b2')]);

      expect(state.beacons, hasLength(2));
      expect(notified, 1);
    });

    test('removeBeacon removes beacon and its cached report', () {
      final state = _makeAppState();
      state.setBeacons([_makeBeacon('b1'), _makeBeacon('b2')]);

      state.removeBeacon('b1');

      expect(state.beacons.map((b) => b.beaconId), isNot(contains('b1')));
      expect(state.beacons, hasLength(1));
    });

    test('updateBeaconOverrides applies name override', () {
      final state = _makeAppState();
      state.setBeacons([_makeBeacon('b1')]);

      state.updateBeaconOverrides('b1', name: 'My Tag');

      expect(state.beacons.first.name, 'My Tag');
    });

    test('updateBeaconOverrides with null clears the override', () {
      final state = _makeAppState();
      state.setBeacons([_makeBeacon('b1')]);

      state.updateBeaconOverrides('b1', name: 'Override');
      expect(state.beacons.first.name, 'Override');

      state.updateBeaconOverrides('b1', name: null);
      // Falls back to originalName
      expect(state.beacons.first.name, 'Beacon b1');
    });

    test('updateBeaconOverrides with no args leaves overrides unchanged', () {
      final state = _makeAppState();
      state.setBeacons([_makeBeacon('b1')]);
      state.updateBeaconOverrides('b1', name: 'A', emoji: '🚗');

      state.updateBeaconOverrides('b1'); // no args

      expect(state.beacons.first.userOverrideName, 'A');
      expect(state.beacons.first.userOverrideEmoji, '🚗');
    });

    test('updateBeaconOverrides ignores unknown beaconId', () {
      final state = _makeAppState();
      state.setBeacons([_makeBeacon('b1')]);
      // Should not throw
      state.updateBeaconOverrides('unknown', name: 'Test');
      expect(state.beacons, hasLength(1));
    });
  });

  group('AppState – report cache', () {
    test('latestReportFor returns null when no reports loaded', () {
      final state = _makeAppState();
      state.setBeacons([_makeBeacon('b1')]);
      expect(state.latestReportFor('b1'), isNull);
    });

    test('refreshReports populates O(1) cache', () async {
      final beacon = _makeBeacon('b1', plist: '<plist/>');

      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'b1': [
              {
                'publishedAt': 1000,
                'timestamp': 1000,
                'latitude': 10.0,
                'longitude': 20.0,
              },
              {
                'publishedAt': 3000,
                'timestamp': 3000,
                'latitude': 11.0,
                'longitude': 21.0,
              },
              {
                'publishedAt': 2000,
                'timestamp': 2000,
                'latitude': 10.5,
                'longitude': 20.5,
              },
            ],
          }),
          200,
        );
      });

      final authService = AppleAuthService(
        storage: InMemoryCredentialStorage(),
      );
      // Inject a logged-in user so refreshReports actually runs.
      final state = AppState(
        authService: authService,
        reportService: BeaconReportService(client: client),
      );
      state.setUser(
          const AppleUserData(email: 'u@e.com', accountToken: 'tok'));
      state.setAnisetteServerUrl('https://ani.example.com');
      state.setBeacons([beacon]);

      await state.refreshReports();

      // Should cache the report with the highest timestamp (3000).
      final latest = state.latestReportFor('b1');
      expect(latest, isNotNull);
      expect(latest!.timestamp, 3000);
      expect(latest.latitude, 11.0);
    });

    test('removeBeacon clears its cached report', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'b1': [
              {
                'publishedAt': 1000,
                'timestamp': 1000,
                'latitude': 10.0,
                'longitude': 20.0,
              },
            ],
          }),
          200,
        );
      });

      final state = AppState(
        authService: AppleAuthService(storage: InMemoryCredentialStorage()),
        reportService: BeaconReportService(client: client),
      );
      state.setUser(
          const AppleUserData(email: 'u@e.com', accountToken: 'tok'));
      state.setAnisetteServerUrl('https://ani.example.com');
      state.setBeacons([_makeBeacon('b1', plist: '<p/>')]);

      await state.refreshReports();
      expect(state.latestReportFor('b1'), isNotNull);

      state.removeBeacon('b1');
      expect(state.latestReportFor('b1'), isNull);
    });

    test('logout clears beacons and report cache', () async {
      final state = _makeAppState();
      state.setBeacons([_makeBeacon('b1')]);

      await state.logout();

      expect(state.beacons, isEmpty);
      expect(state.latestReportFor('b1'), isNull);
      expect(state.isLoggedIn, isFalse);
    });
  });
}
