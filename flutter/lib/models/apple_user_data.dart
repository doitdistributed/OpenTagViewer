import 'package:flutter/foundation.dart';

/// Holds the current Apple account session data.
@immutable
class AppleUserData {
  final String email;

  /// Encrypted or opaque account token returned by the Anisette/FindMy stack.
  final String accountToken;

  const AppleUserData({
    required this.email,
    required this.accountToken,
  });

  @override
  String toString() => 'AppleUserData(email: $email)';
}
