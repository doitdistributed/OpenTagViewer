import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:opentagviewer/services/apple_auth_service.dart';
import 'package:opentagviewer/services/anisette_service.dart';

void main() {
  group('AnisetteService', () {
    test('fetchServerSuggestions parses JSON response', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'SideStore': 'https://ani.sidestore.io'}),
          200,
        );
      });

      final service = AnisetteService(client: client);
      final suggestions = await service.fetchServerSuggestions();

      expect(suggestions, hasLength(1));
      expect(suggestions.first.name, 'SideStore');
      expect(suggestions.first.url, 'https://ani.sidestore.io');
    });

    test('testServer returns true on HTTP 200', () async {
      final client = MockClient((request) async => http.Response('ok', 200));
      final service = AnisetteService(client: client);
      expect(await service.testServer('https://example.com'), isTrue);
    });

    test('testServer returns false on non-200', () async {
      final client =
          MockClient((request) async => http.Response('error', 503));
      final service = AnisetteService(client: client);
      expect(await service.testServer('https://example.com'), isFalse);
    });
  });

  group('AppleAuthService', () {
    AppleAuthService makeService(MockClient client) {
      return AppleAuthService(
        httpClient: client,
        storage: InMemoryCredentialStorage(),
      );
    }

    test('login returns loggedIn state on success', () async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/login')) {
          return http.Response(
            jsonEncode({
              'loginState': 'LOGGED_IN',
              'accountToken': 'token123',
            }),
            200,
          );
        }
        return http.Response('not found', 404);
      });

      final service = makeService(client);
      final response = await service.login(
        email: 'test@example.com',
        password: 'secret',
        anisetteServerUrl: 'https://ani.example.com',
      );

      expect(response.state, LoginState.loggedIn);
      expect(response.user?.email, 'test@example.com');
    });

    test('login returns twoFactorRequired with methods', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'loginState': '2FA_REQUIRED',
            'loginMethods': [
              {'type': 1, 'methodId': 'm1', 'phoneNumber': '+1234'},
              {'type': 0, 'methodId': 'm2'},
            ],
          }),
          200,
        );
      });

      final service = makeService(client);
      final response = await service.login(
        email: 'test@example.com',
        password: 'secret',
        anisetteServerUrl: 'https://ani.example.com',
      );

      expect(response.state, LoginState.twoFactorRequired);
      expect(response.authMethods, hasLength(2));
      expect(response.authMethods!.first.type, TwoFactorMethod.phone);
      expect(response.authMethods!.first.phoneNumber, '+1234');
      expect(response.authMethods!.last.type, TwoFactorMethod.trustedDevice);
    });

    test('login throws AppleLoginException when body contains error key', () {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'error': 'Invalid credentials'}),
          200,
        );
      });

      final service = makeService(client);
      expect(
        () => service.login(
          email: 'bad@example.com',
          password: 'wrong',
          anisetteServerUrl: 'https://ani.example.com',
        ),
        throwsA(isA<AppleLoginException>()),
      );
    });

    test('login throws AppleLoginException on HTTP error with status in message',
        () async {
      final client =
          MockClient((request) async => http.Response('Server Error', 500));

      final service = makeService(client);
      expect(
        () => service.login(
          email: 'test@example.com',
          password: 'pass',
          anisetteServerUrl: 'https://ani.example.com',
        ),
        throwsA(
          predicate<AppleLoginException>(
            (e) => e.message.contains('500'),
            'exception message should contain HTTP status code',
          ),
        ),
      );
    });

    test('getStoredUser returns null when no credentials stored', () async {
      final service = AppleAuthService(
        storage: InMemoryCredentialStorage(),
      );
      expect(await service.getStoredUser(), isNull);
    });

    test('getStoredUser returns user after successful login', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'loginState': 'LOGGED_IN',
            'accountToken': 'mytoken',
          }),
          200,
        );
      });

      final service = makeService(client);
      await service.login(
        email: 'user@example.com',
        password: 'pass',
        anisetteServerUrl: 'https://ani.example.com',
      );

      final stored = await service.getStoredUser();
      expect(stored?.email, 'user@example.com');
      expect(stored?.accountToken, 'mytoken');
    });

    test('logout clears stored credentials', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'loginState': 'LOGGED_IN',
            'accountToken': 'tok',
          }),
          200,
        );
      });

      final service = makeService(client);
      await service.login(
        email: 'user@example.com',
        password: 'pass',
        anisetteServerUrl: 'https://ani.example.com',
      );

      await service.logout();
      expect(await service.getStoredUser(), isNull);
    });
  });
}
