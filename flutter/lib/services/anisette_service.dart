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
  static const String defaultAnisetteUrl = 'https://omni.parallel-ing.net/';
  static const String _sideStoreServersUrl =
      'https://raw.githubusercontent.com/SideStore/anisette-servers/main/servers.json';

  final http.Client _client;

  AnisetteService({http.Client? client}) : _client = client ?? http.Client();

  /// Releases the underlying HTTP client. Call when the service is no longer
  /// needed (e.g. from a [ChangeNotifier.dispose] override).
  void dispose() => _client.close();

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
      final headers = await fetchAnisetteHeaders(serverUrl);
      return headers.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Fetches the Anisette headers from the given [serverUrl].
  Future<Map<String, String>> fetchAnisetteHeaders(String serverUrl) async {
      final url = serverUrl.endsWith('/') ? serverUrl : '$serverUrl/';
      final response = await _client.get(Uri.parse(url));
      
      if (response.statusCode != 200) {
        throw Exception('Failed to fetch Anisette headers (HTTP ${response.statusCode})');
      }
      
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      
      final headers = <String, String>{};
      data.forEach((key, value) {
          final lowerKey = key.toLowerCase();
          if (lowerKey != 'host' && 
              lowerKey != 'content-length' && 
              lowerKey != 'connection') {
              headers[key] = value.toString();
          }
      });
      return headers;
  }
}
