import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../models/beacon_information.dart';

/// Thrown when an import .zip file cannot be processed.
class ZipImporterException implements Exception {
  final String message;
  const ZipImporterException(this.message);

  @override
  String toString() => 'ZipImporterException: $message';
}

/// Data extracted from an OpenTagViewer export .zip file.
class ImportData {
  final String exportInfoYaml;
  final Map<String, String> ownedBeaconPLists;
  final Map<String, String> beaconNamingRecordPLists;

  const ImportData({
    required this.exportInfoYaml,
    required this.ownedBeaconPLists,
    required this.beaconNamingRecordPLists,
  });
}

/// Parses an OpenTagViewer export .zip and extracts beacon data.
///
/// The expected zip structure is:
/// ```
/// OPENTAGVIEWER.yml
/// OwnedBeacons/<beacon-uuid>.plist
/// BeaconNamingRecord/<beacon-uuid>/<naming-record-uuid>.plist
/// ```
class BeaconImportService {
  static final _ownedBeaconPattern = RegExp(
      r'^OwnedBeacons/([0-9A-F]{8}-[0-9A-F]{4}-4[0-9A-F]{3}-[89AB][0-9A-F]{3}-[0-9A-F]{12})\.plist$');
  static final _namingRecordPattern = RegExp(
      r'^BeaconNamingRecord/([0-9A-F]{8}-[0-9A-F]{4}-4[0-9A-F]{3}-[89AB][0-9A-F]{3}-[0-9A-F]{12})/([0-9A-F]{8}-[0-9A-F]{4}-4[0-9A-F]{3}-[89AB][0-9A-F]{3}-[0-9A-F]{12})\.plist$');
  static final _exportInfoPattern = RegExp(r'^OPENTAGVIEWER\.yml$');

  /// Extracts and parses the contents of the zip [bytes].
  ///
  /// Returns an [ImportData] containing all parsed plist strings, keyed by
  /// beacon UUID.
  ImportData extractZip(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);

    String? exportYaml;
    final ownedBeacons = <String, String>{};
    final namingRecords = <String, String>{};

    for (final file in archive) {
      if (!file.isFile) continue;
      final name = file.name;
      final content = String.fromCharCodes(file.content as List<int>);

      if (_exportInfoPattern.hasMatch(name)) {
        exportYaml = content;
        continue;
      }

      final ownedMatch = _ownedBeaconPattern.firstMatch(name);
      if (ownedMatch != null) {
        final beaconId = ownedMatch.group(1)!;
        ownedBeacons[beaconId] = content;
        continue;
      }

      final namingMatch = _namingRecordPattern.firstMatch(name);
      if (namingMatch != null) {
        final beaconId = namingMatch.group(1)!;
        // Only keep the first naming record per beacon (consistent with the Android app).
        if (!namingRecords.containsKey(beaconId)) {
          namingRecords[beaconId] = content;
        }
      }
    }

    if (exportYaml == null) {
      throw const ZipImporterException(
          'OPENTAGVIEWER.yml not found in the zip file. '
          'Please export again using the OpenTagViewer macOS app.');
    }

    return ImportData(
      exportInfoYaml: exportYaml,
      ownedBeaconPLists: ownedBeacons,
      beaconNamingRecordPLists: namingRecords,
    );
  }

  /// Parses the [ImportData] into a list of [BeaconInformation] models.
  List<BeaconInformation> parseBeacons(ImportData importData) {
    final result = <BeaconInformation>[];

    final parseErrors = <String, Object>{};

    for (final entry in importData.ownedBeaconPLists.entries) {
      final beaconId = entry.key;
      final ownedPList = entry.value;
      final namingPList = importData.beaconNamingRecordPLists[beaconId];

      try {
        final beacon = _parseBeacon(
          beaconId: beaconId,
          ownedBeaconPList: ownedPList,
          namingRecordPList: namingPList,
        );
        result.add(beacon);
      } catch (e) {
        // Skip beacons that cannot be parsed rather than failing the entire
        // import, but record the failure so callers can surface it if needed.
        parseErrors[beaconId] = e;
      }
    }

    if (parseErrors.isNotEmpty) {
      // Surface parse errors as a warning string in debug mode.
      assert(() {
        for (final entry in parseErrors.entries) {
          // ignore: avoid_print
          print('[BeaconImportService] Failed to parse beacon '
              '${entry.key}: ${entry.value}');
        }
        return true;
      }());
    }

    return result;
  }

  // ---------------------------------------------------------------------------

  BeaconInformation _parseBeacon({
    required String beaconId,
    required String ownedBeaconPList,
    String? namingRecordPList,
  }) {
    final ownedDoc = XmlDocument.parse(ownedBeaconPList);

    final batteryLevel = _intFromPList(ownedDoc, 'batteryLevel') ?? 0;
    final model = _stringFromPList(ownedDoc, 'model');
    final pairingDate = _stringFromPList(ownedDoc, 'pairingDate');
    final productId = _intFromPList(ownedDoc, 'productId') ?? -1;
    final systemVersion = _stringFromPList(ownedDoc, 'systemVersion');
    final vendorId = _intFromPList(ownedDoc, 'vendorId') ?? -1;

    final stableId = _firstArrayItemFromPList(ownedDoc, 'stableIdentifier');
    final stableIdentifiers = stableId != null ? [stableId] : <String>[];

    String? emoji;
    String? name;
    String? namingRecordId;

    if (namingRecordPList != null) {
      final namingDoc = XmlDocument.parse(namingRecordPList);
      emoji = _stringFromPList(namingDoc, 'emoji');
      name = _stringFromPList(namingDoc, 'name');
      namingRecordId = _stringFromPList(namingDoc, 'identifier');
    }

    return BeaconInformation(
      beaconId: beaconId,
      namingRecordId: namingRecordId,
      originalEmoji: emoji,
      originalName: name,
      ownedBeaconPlistRaw: ownedBeaconPList,
      batteryLevel: batteryLevel,
      model: model,
      pairingDate: pairingDate,
      productId: productId,
      stableIdentifier: stableIdentifiers,
      systemVersion: systemVersion,
      vendorId: vendorId,
    );
  }

  // Retrieves the text value of the <string> element that follows a <key>
  // matching [keyName] inside the root <dict> of a plist document.
  String? _stringFromPList(XmlDocument doc, String keyName) {
    try {
      final keys = doc.findAllElements('key');
      for (final key in keys) {
        if (key.innerText == keyName) {
          final next = _nextSiblingElement(key);
          if (next != null && (next.name.local == 'string' || next.name.local == 'date')) {
            return next.innerText.trim();
          }
          return null;
        }
      }
    } catch (_) {}
    return null;
  }

  int? _intFromPList(XmlDocument doc, String keyName) {
    try {
      final keys = doc.findAllElements('key');
      for (final key in keys) {
        if (key.innerText == keyName) {
          final next = _nextSiblingElement(key);
          if (next != null && next.name.local == 'integer') {
            return int.tryParse(next.innerText.trim());
          }
          return null;
        }
      }
    } catch (_) {}
    return null;
  }

  String? _firstArrayItemFromPList(XmlDocument doc, String keyName) {
    try {
      final keys = doc.findAllElements('key');
      for (final key in keys) {
        if (key.innerText == keyName) {
          final next = _nextSiblingElement(key);
          if (next != null && next.name.local == 'array') {
            final child = next.children
                .whereType<XmlElement>()
                .firstOrNull;
            return child?.innerText.trim();
          }
          return null;
        }
      }
    } catch (_) {}
    return null;
  }

  XmlElement? _nextSiblingElement(XmlElement element) {
    var sibling = element.nextSibling;
    while (sibling != null) {
      if (sibling is XmlElement) return sibling;
      sibling = sibling.nextSibling;
    }
    return null;
  }
}
