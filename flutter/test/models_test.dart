import 'package:flutter_test/flutter_test.dart';

import 'package:opentagviewer/models/beacon_information.dart';
import 'package:opentagviewer/models/beacon_location_report.dart';

void main() {
  group('BeaconInformation', () {
    test('isAirTag returns true for productId == 21760', () {
      final beacon = BeaconInformation(
        beaconId: 'test-id',
        productId: 21760,
      );
      expect(beacon.isAirTag, isTrue);
    });

    test('isAirTag returns false for other productIds', () {
      final beacon = BeaconInformation(
        beaconId: 'test-id',
        productId: -1,
      );
      expect(beacon.isAirTag, isFalse);
    });

    test('isIpad returns true when model contains "iPad"', () {
      final beacon = BeaconInformation(
        beaconId: 'test-id',
        model: 'iPad13,18',
      );
      expect(beacon.isIpad, isTrue);
    });

    test('isIpad returns false for AirTag (empty model)', () {
      final beacon = BeaconInformation(
        beaconId: 'test-id',
        model: '',
        productId: 21760,
      );
      expect(beacon.isIpad, isFalse);
    });

    test('name returns userOverrideName when set', () {
      final beacon = BeaconInformation(
        beaconId: 'test-id',
        originalName: 'Original',
        userOverrideName: 'Override',
      );
      expect(beacon.name, 'Override');
    });

    test('name falls back to originalName when no override', () {
      final beacon = BeaconInformation(
        beaconId: 'test-id',
        originalName: 'Original',
      );
      expect(beacon.name, 'Original');
    });

    test('emoji returns userOverrideEmoji when set', () {
      final beacon = BeaconInformation(
        beaconId: 'test-id',
        originalEmoji: '🔑',
        userOverrideEmoji: '🚗',
      );
      expect(beacon.emoji, '🚗');
    });

    test('isEmojiFilled returns false when no emoji set', () {
      final beacon = BeaconInformation(beaconId: 'test-id');
      expect(beacon.isEmojiFilled, isFalse);
    });

    test('isEmojiFilled returns true when emoji is set', () {
      final beacon = BeaconInformation(
        beaconId: 'test-id',
        originalEmoji: '🔑',
      );
      expect(beacon.isEmojiFilled, isTrue);
    });

    test('copyWith preserves original fields', () {
      final original = BeaconInformation(
        beaconId: 'test-id',
        originalName: 'Original',
        productId: 21760,
        batteryLevel: 1,
      );
      final copy = original.copyWith(userOverrideName: 'Copy Name');

      expect(copy.beaconId, original.beaconId);
      expect(copy.productId, original.productId);
      expect(copy.batteryLevel, original.batteryLevel);
      expect(copy.userOverrideName, 'Copy Name');
    });
  });

  group('BeaconLocationReport', () {
    test('equality is based on publishedAt, timestamp, lat, lon', () {
      const r1 = BeaconLocationReport(
        publishedAt: 1000,
        timestamp: 2000,
        latitude: 51.5,
        longitude: -0.1,
      );
      const r2 = BeaconLocationReport(
        publishedAt: 1000,
        timestamp: 2000,
        latitude: 51.5,
        longitude: -0.1,
        confidence: 3,
      );
      expect(r1, equals(r2));
    });

    test('dateTime converts timestamp to local DateTime', () {
      const report = BeaconLocationReport(
        publishedAt: 0,
        timestamp: 0,
        latitude: 0,
        longitude: 0,
      );
      // Epoch in UTC should give a valid DateTime
      expect(report.dateTime, isA<DateTime>());
    });
  });
}
