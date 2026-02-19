import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:opentagviewer/services/beacon_import_service.dart';

// A minimal valid Apple plist XML fragment for an OwnedBeacon
const _ownedBeaconPlist = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>batteryLevel</key><integer>0</integer>
    <key>model</key><string></string>
    <key>pairingDate</key><date>2024-01-15T12:00:00Z</date>
    <key>productId</key><integer>21760</integer>
    <key>stableIdentifier</key>
    <array>
        <string>AABBCCDD-1234-4321-AABB-AABBCCDD1234</string>
    </array>
    <key>systemVersion</key><string>2.0.73</string>
    <key>vendorId</key><integer>76</integer>
    <key>privateKey</key><data>c29tZWRhdGE=</data>
</dict>
</plist>''';

const _namingRecordPlist = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>identifier</key><string>AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEEEE</string>
    <key>associatedBeacon</key><string>11111111-2222-4333-8444-555555555555</string>
    <key>emoji</key><string>🔑</string>
    <key>name</key><string>My Keys</string>
</dict>
</plist>''';

const _beaconId = '11111111-2222-4333-8444-555555555555';
const _namingId = 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEEEE';

Uint8List _buildTestZip({bool includeYaml = true}) {
  final encoder = ZipEncoder();
  final archive = Archive();

  if (includeYaml) {
    archive.addFile(ArchiveFile(
      'OPENTAGVIEWER.yml',
      0,
      utf8.encode('version: 1\n'),
    ));
  }

  archive.addFile(ArchiveFile(
    'OwnedBeacons/$_beaconId.plist',
    0,
    utf8.encode(_ownedBeaconPlist),
  ));

  archive.addFile(ArchiveFile(
    'BeaconNamingRecord/$_beaconId/$_namingId.plist',
    0,
    utf8.encode(_namingRecordPlist),
  ));

  return Uint8List.fromList(encoder.encode(archive)!);
}

void main() {
  late BeaconImportService service;

  setUp(() => service = BeaconImportService());

  group('BeaconImportService.extractZip', () {
    test('successfully extracts a valid zip', () {
      final data = service.extractZip(_buildTestZip());
      expect(data.ownedBeaconPLists, contains(_beaconId));
      expect(data.beaconNamingRecordPLists, contains(_beaconId));
      expect(data.exportInfoYaml, contains('version'));
    });

    test('throws ZipImporterException when OPENTAGVIEWER.yml is missing', () {
      expect(
        () => service.extractZip(_buildTestZip(includeYaml: false)),
        throwsA(isA<ZipImporterException>()),
      );
    });
  });

  group('BeaconImportService.parseBeacons', () {
    test('parses beacon info from plist XML', () {
      final importData = service.extractZip(_buildTestZip());
      final beacons = service.parseBeacons(importData);

      expect(beacons, hasLength(1));

      final b = beacons.first;
      expect(b.beaconId, _beaconId);
      expect(b.isAirTag, isTrue); // productId == 21760
      expect(b.name, 'My Keys');
      expect(b.emoji, '🔑');
      expect(b.systemVersion, '2.0.73');
      expect(b.vendorId, 76);
      expect(b.batteryLevel, 0);
      expect(b.stableIdentifier, contains('AABBCCDD-1234-4321-AABB-AABBCCDD1234'));
    });
  });
}
