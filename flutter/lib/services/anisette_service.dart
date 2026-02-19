import 'dart:convert';
import 'package:http/http.dart' as http;

/// Represents an Anisette server suggestion fetched from the SideStore list.
class AnisetteServerSuggestion {
  final String name;
  final String url;

  const AnisetteServerSuggestion({required this.name, required this.url});
}

/// Fetches and tests Anisette server availability.
///
/// Anisette servers are required to generate Apple authentication headers
/// for the FindMy network requests. The list of public servers is maintained
/// by the SideStore project at:
/// https://github.com/SideStore/anisette-servers/blob/main/servers.json
class AnisetteService {
  static const String defaultAnisetteUrl = 'https://ani.sidestore.io';
  static const String _sideStoreServersUrl =
      'https://raw.githubusercontent.com/SideStore/anisette-servers/main/servers.json';

  final http.Client _client;

  AnisetteService({http.Client? client}) : _client = client ?? http.Client();

  /// Fetches the list of suggested public Anisette servers from the
  /// SideStore GitHub repository.
  Future<List<AnisetteServerSuggestion>> fetchServerSuggestions() async {
    final response = await _client.get(Uri.parse(_sideStoreServersUrl));
    if (response.statusCode != 200) {
      throw Exception(
          'Failed to fetch Anisette server list (HTTP ${response.statusCode})');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data.entries.map((e) {
      return AnisetteServerSuggestion(name: e.key, url: e.value as String);
    }).toList();
  }

  /// Tests whether [serverUrl] is reachable and returns a valid Anisette
  /// response. Returns [true] on success.
  Future<bool> testServer(String serverUrl) async {
    try {
      final url = serverUrl.endsWith('/')
          ? '${serverUrl}v3/client_info'
          : '$serverUrl/v3/client_info';
      final response =
          await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
