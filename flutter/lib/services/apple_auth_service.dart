import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../models/apple_user_data.dart';

/// Thrown when Apple account login fails.
class AppleLoginException implements Exception {
  final String message;
  const AppleLoginException(this.message);

  @override
  String toString() => 'AppleLoginException: $message';
}

/// Abstraction over key-value credential storage.
///
/// The default implementation delegates to [FlutterSecureStorage].
/// Tests may supply an in-memory implementation.
abstract class CredentialStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Default implementation backed by [FlutterSecureStorage].
class SecureCredentialStorage implements CredentialStorage {
  final FlutterSecureStorage _storage;

  SecureCredentialStorage([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// In-memory [CredentialStorage] for use in tests.
class InMemoryCredentialStorage implements CredentialStorage {
  final Map<String, String> _store = {};

  @override
  Future<String?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, String value) async =>
      _store[key] = value;

  @override
  Future<void> delete(String key) async => _store.remove(key);
}

/// Login state returned after an initial credential submission.
enum LoginState {
  /// Credentials were accepted, no further action needed.
  loggedIn,

  /// Apple requires two-factor authentication before the session is valid.
  twoFactorRequired,
}

/// Type of 2FA method offered by Apple.
enum TwoFactorMethod {
  trustedDevice,
  phone,
  unknown,
}

/// Describes a single available 2FA method.
class AuthMethod {
  final TwoFactorMethod type;

  /// Phone number (only set when [type] == [TwoFactorMethod.phone]).
  final String? phoneNumber;

  /// Opaque identifier used to request the verification code.
  final String methodId;

  const AuthMethod({
    required this.type,
    required this.methodId,
    this.phoneNumber,
  });
}

/// Encapsulates the response from an initial login attempt.
class LoginResponse {
  final LoginState state;
  final List<AuthMethod>? authMethods;

  /// Non-null when [state] == [LoginState.loggedIn].
  final AppleUserData? user;

  const LoginResponse({
    required this.state,
    this.authMethods,
    this.user,
  });
}

/// Handles Apple account authentication via an Anisette server.
///
/// Authentication follows the same flow used by the Android app:
/// 1. Submit email + password to the Anisette-backed endpoint.
/// 2. If 2FA is required, request a code via the selected method.
/// 3. Submit the 6-digit code to complete authentication.
///
/// Credentials are persisted via [CredentialStorage] (defaults to
/// [SecureCredentialStorage] backed by [FlutterSecureStorage]).
class AppleAuthService {
  static const String _keyEmail = 'apple_email';
  static const String _keyToken = 'apple_account_token';

  final http.Client _httpClient;
  final CredentialStorage _storage;

  AppleAuthService({
    http.Client? httpClient,
    CredentialStorage? storage,
  })  : _httpClient = httpClient ?? http.Client(),
        _storage = storage ?? SecureCredentialStorage();

  /// Returns the stored [AppleUserData] if a previous session exists,
  /// or [null] if the user has not logged in.
  Future<AppleUserData?> getStoredUser() async {
    final email = await _storage.read(_keyEmail);
    final token = await _storage.read(_keyToken);
    if (email != null && token != null) {
      return AppleUserData(email: email, accountToken: token);
    }
    return null;
  }

  /// Initiates an Apple ID login using the supplied [anisetteServerUrl].
  ///
  /// Returns a [LoginResponse] that describes whether the login succeeded
  /// immediately or whether 2FA is required.
  Future<LoginResponse> login({
    required String email,
    required String password,
    required String anisetteServerUrl,
  }) async {
    final uri = Uri.parse('$anisetteServerUrl/login');
    final response = await _httpClient.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
      }),
    );

    final body = _tryDecodeBody(response.body);

    if (response.statusCode != 200 || body.containsKey('error')) {
      final errorMsg = body['error'] as String? ??
          'Login failed (HTTP ${response.statusCode})';
      throw AppleLoginException(errorMsg);
    }

    final stateStr = body['loginState'] as String? ?? '';

    if (stateStr == 'LOGGED_IN') {
      final token = body['accountToken'] as String? ?? '';
      final user = AppleUserData(email: email, accountToken: token);
      await _persistUser(user);
      return LoginResponse(state: LoginState.loggedIn, user: user);
    }

    // 2FA required – parse available methods
    final rawMethods = body['loginMethods'] as List<dynamic>? ?? [];
    final methods = rawMethods.map((m) {
      final map = m as Map<String, dynamic>;
      final typeInt = map['type'] as int? ?? -1;
      final TwoFactorMethod type;
      switch (typeInt) {
        case 0:
          type = TwoFactorMethod.trustedDevice;
          break;
        case 1:
          type = TwoFactorMethod.phone;
          break;
        default:
          type = TwoFactorMethod.unknown;
      }
      return AuthMethod(
        type: type,
        methodId: map['methodId'] as String? ?? '',
        phoneNumber: map['phoneNumber'] as String?,
      );
    }).toList();

    return LoginResponse(
      state: LoginState.twoFactorRequired,
      authMethods: methods,
    );
  }

  /// Requests that Apple sends a 2FA code via the given [method].
  Future<void> requestTwoFactorCode({
    required String anisetteServerUrl,
    required AuthMethod method,
  }) async {
    final uri = Uri.parse('$anisetteServerUrl/request_2fa');
    final response = await _httpClient.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'methodId': method.methodId}),
    );
    if (response.statusCode != 200) {
      throw AppleLoginException('Failed to request 2FA code');
    }
  }

  /// Submits the 6-digit [code] to complete 2FA and finalise the session.
  Future<AppleUserData> submitTwoFactorCode({
    required String email,
    required String anisetteServerUrl,
    required AuthMethod method,
    required String code,
  }) async {
    final uri = Uri.parse('$anisetteServerUrl/verify_2fa');
    final response = await _httpClient.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'methodId': method.methodId, 'code': code}),
    );

    if (response.statusCode != 200) {
      final body = _tryDecodeBody(response.body);
      throw AppleLoginException(
          body['error'] as String? ?? '2FA verification failed');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final token = body['accountToken'] as String? ?? '';
    final user = AppleUserData(email: email, accountToken: token);
    await _persistUser(user);
    return user;
  }

  /// Removes stored credentials (logout).
  Future<void> logout() async {
    await _storage.delete(_keyEmail);
    await _storage.delete(_keyToken);
  }

  // ---------------------------------------------------------------------------

  Future<void> _persistUser(AppleUserData user) async {
    await _storage.write(_keyEmail, user.email);
    await _storage.write(_keyToken, user.accountToken);
  }

  Map<String, dynamic> _tryDecodeBody(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }
}
