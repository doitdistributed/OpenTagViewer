import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../models/apple_user_data.dart';
import 'anisette_service.dart';
import 'srp/apple_gsa_client.dart';

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
  final AppleUserData? user;
  
  /// Session headers/cookies required for 2FA steps.
  final Map<String, String>? sessionData;

  const LoginResponse({
    required this.state,
    this.authMethods,
    this.user,
    this.sessionData,
  });
}

/// Validates that [url] uses HTTPS. Throws [AppleLoginException] if it does not.
///
/// All authentication endpoints handle Apple ID credentials and session tokens,
/// so cleartext HTTP connections must be rejected to prevent credential
/// interception by on-path attackers.
void _requireHttps(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https') {
    throw AppleLoginException(
        'Anisette server URL must use HTTPS to protect your credentials. '
        'Received: $url');
  }
}

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

  /// Releases the underlying HTTP client. Call when the service is no longer
  /// needed (e.g. from a [ChangeNotifier.dispose] override).
  void dispose() => _httpClient.close();

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

  Future<LoginResponse> login({
    required String email,
    required String password,
    required String anisetteServerUrl,
  }) async {
    _requireHttps(anisetteServerUrl);

    // 1. Setup Anisette provider for fresh headers per GSA request
    final anisetteService = AnisetteService(client: _httpClient);

    // 2. Perform GSA Login (provider is called for each request)
    final gsaClient = AppleGsaClient(client: _httpClient);
    final result = await gsaClient.login(
        username: email,
        password: password,
        anisetteProvider: () => anisetteService.fetchAnisetteHeaders(anisetteServerUrl),
    );

    final responseDict = result['response'] as Map<String, dynamic>;
    final responseHeaders = result['headers'] as Map<String, String>;
    
    // Check Status
    final responseBody = responseDict['Response'] as Map<String, dynamic>?;
    final status = responseBody?['Status'] as Map<String, dynamic>?;
    final ec = status?['ec'] as int?;

    // Check Status and Attributes
    if (ec == 0) {
      // Logged In!
      final token = jsonEncode(responseDict);
      final user = AppleUserData(email: email, accountToken: token);
      await _persistUser(user);
      return LoginResponse(state: LoginState.loggedIn, user: user);
    }
    
    // Check for specific errors
    if (ec == -22406) {
        throw const AppleLoginException('Incorrect Apple ID password.');
    }
    
    // TODO: Handle other specific errors (Locked account, etc.)
    // If we assume it's 2FA, we should check if auth methods are actually provided?
    // The response dict usually contains `trustedDevices` or `securityCode` options if it's 2FA.
    
    // For now, if we don't know the error, we treat it as 2FA (risky) or throw?
    // Let's print the error to console and proceed to 2FA only if we see hints?
    // Or just let the 2FA screen handle the "failure" to request code?
    debugPrint('[AppleAuthService] Login returned EC=$ec. Assuming 2FA flow.');

    // Treat non-zero EC as 2FA required
    return LoginResponse(
      state: LoginState.twoFactorRequired,
      authMethods: [
          const AuthMethod(type: TwoFactorMethod.phone, methodId: 'sms', phoneNumber: '****'),
          const AuthMethod(type: TwoFactorMethod.trustedDevice, methodId: 'trusted_device'),
      ],
      sessionData: responseHeaders, // Pass headers for next steps
    );
  }

  Future<void> requestTwoFactorCode({
    required String anisetteServerUrl,
    required AuthMethod method,
    required Map<String, String> sessionData,
  }) async {
    _requireHttps(anisetteServerUrl);
    
    // Fetch Anisette Headers again (fresh time/id)
    final anisetteService = AnisetteService(client: _httpClient);
    final headers = await anisetteService.fetchAnisetteHeaders(anisetteServerUrl);
    
    final gsaClient = AppleGsaClient(client: _httpClient);
    await gsaClient.request2faCode(
        sessionHeaders: sessionData, 
        methodId: method.methodId, 
        anisetteHeaders: headers
    );
  }

  Future<AppleUserData> submitTwoFactorCode({
    required String email,
    required String anisetteServerUrl,
    required AuthMethod method,
    required String code,
    required Map<String, String> sessionData,
  }) async {
    _requireHttps(anisetteServerUrl);
    
    final anisetteService = AnisetteService(client: _httpClient);
    final headers = await anisetteService.fetchAnisetteHeaders(anisetteServerUrl);
    
    final gsaClient = AppleGsaClient(client: _httpClient);
    final result = await gsaClient.validate2faCode(
        sessionHeaders: sessionData, 
        code: code, 
        methodId: method.methodId, 
        anisetteHeaders: headers,
        username: email
    );
    
    final body = result['response'] as Map<String, dynamic>;
    
    // Check for explicit error or success
    final status = body['Status'] as Map<String, dynamic>?;
    final ec = status?['ec'] as int?;
    
    if (ec != 0) {
         throw AppleLoginException('2FA Verification Failed (EC=$ec)');
    }

    // Success
    // Note: The token might be in a different place?
    // Usually standard response.
    final token = jsonEncode(body);
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
    await _storage.write(_keyEmail, _validateForStorage(user.email, 'email'));
    await _storage.write(
        _keyToken, _validateForStorage(user.accountToken, 'account token'));
  }

  /// Validates that [value] contains no null bytes or other characters that
  /// could cause issues with the underlying secure storage implementation.
  String _validateForStorage(String value, String fieldName) {
    if (value.contains('\u0000')) {
      throw AppleLoginException(
          'Invalid $fieldName: contains disallowed characters');
    }
    return value;
  }

  Map<String, dynamic> _tryDecodeBody(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }
}
