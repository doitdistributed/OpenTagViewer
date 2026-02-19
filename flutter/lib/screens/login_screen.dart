import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/apple_auth_service.dart';
import '../services/anisette_service.dart';
import '../state/app_state.dart';
import 'device_list_screen.dart';

/// Handles Apple ID login, including the 2FA step.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _anisetteController = TextEditingController(
      text: AnisetteService.defaultAnisetteUrl);
  final _codeController = TextEditingController();

  bool _loading = false;
  String? _errorMessage;

  LoginResponse? _pendingLoginResponse;
  AuthMethod? _selected2FAMethod;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _anisetteController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submitCredentials() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    final appState = context.read<AppState>();
    final authService = AppleAuthService();

    try {
      final response = await authService.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        anisetteServerUrl: _anisetteController.text.trim(),
      );

      if (!mounted) return;

      if (response.state == LoginState.loggedIn && response.user != null) {
        appState.setUser(response.user!);
        appState.setAnisetteServerUrl(_anisetteController.text.trim());
        _navigateToDeviceList();
        return;
      }

      // 2FA required
      setState(() {
        _pendingLoginResponse = response;
        _selected2FAMethod = response.authMethods?.firstOrNull;
      });
    } on AppleLoginException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Unexpected error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _requestCode() async {
    final method = _selected2FAMethod;
    if (method == null) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      await AppleAuthService().requestTwoFactorCode(
        anisetteServerUrl: _anisetteController.text.trim(),
        method: method,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Failed to request code: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitCode() async {
    final method = _selected2FAMethod;
    if (method == null) return;
    if (_codeController.text.trim().length != 6) {
      setState(() => _errorMessage = 'Please enter the 6-digit code');
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    final appState = context.read<AppState>();

    try {
      final user = await AppleAuthService().submitTwoFactorCode(
        email: _emailController.text.trim(),
        anisetteServerUrl: _anisetteController.text.trim(),
        method: method,
        code: _codeController.text.trim(),
      );
      if (!mounted) return;
      appState.setUser(user);
      appState.setAnisetteServerUrl(_anisetteController.text.trim());
      _navigateToDeviceList();
    } on AppleLoginException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Unexpected error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _navigateToDeviceList() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const DeviceListScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final is2FA = _pendingLoginResponse != null;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 48),
                Icon(
                  Icons.location_on,
                  size: 72,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'OpenTagViewer',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Sign in with your Apple ID to view your AirTags',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 40),
                if (!is2FA) ...[
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'Apple ID (email)',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Please enter your Apple ID email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock_outline),
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                    textInputAction: TextInputAction.next,
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return 'Please enter your password';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _anisetteController,
                    decoration: const InputDecoration(
                      labelText: 'Anisette Server URL',
                      prefixIcon: Icon(Icons.dns_outlined),
                      border: OutlineInputBorder(),
                      helperText:
                          'Required for Apple authentication. Keep the default unless you know what you\'re doing.',
                      helperMaxLines: 2,
                    ),
                    keyboardType: TextInputType.url,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Please enter an Anisette server URL';
                      }
                      return null;
                    },
                  ),
                ],
                if (is2FA) ...[
                  Text(
                    'Two-Factor Authentication',
                    style: theme.textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Apple requires a verification code. Select a method and tap "Request Code", then enter the code you receive.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  if (_pendingLoginResponse?.authMethods != null)
                    DropdownButtonFormField<AuthMethod>(
                      value: _selected2FAMethod,
                      decoration: const InputDecoration(
                        labelText: '2FA Method',
                        border: OutlineInputBorder(),
                      ),
                      items: _pendingLoginResponse!.authMethods!
                          .map((m) => DropdownMenuItem(
                                value: m,
                                child: Text(_methodLabel(m)),
                              ))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _selected2FAMethod = v),
                    ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.send),
                    label: const Text('Request Code'),
                    onPressed: _loading ? null : _requestCode,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _codeController,
                    decoration: const InputDecoration(
                      labelText: '6-digit verification code',
                      prefixIcon: Icon(Icons.pin_outlined),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                  ),
                ],
                const SizedBox(height: 8),
                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(color: theme.colorScheme.error),
                      textAlign: TextAlign.center,
                    ),
                  ),
                FilledButton(
                  onPressed: _loading
                      ? null
                      : (is2FA ? _submitCode : _submitCredentials),
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(is2FA ? 'Verify Code' : 'Sign In'),
                ),
                if (is2FA) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () => setState(() {
                              _pendingLoginResponse = null;
                              _selected2FAMethod = null;
                              _codeController.clear();
                              _errorMessage = null;
                            }),
                    child: const Text('Back to Sign In'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _methodLabel(AuthMethod method) {
    switch (method.type) {
      case TwoFactorMethod.phone:
        return 'SMS to ${method.phoneNumber ?? 'phone'}';
      case TwoFactorMethod.trustedDevice:
        return 'Trusted Device';
      case TwoFactorMethod.unknown:
        return 'Other method';
    }
  }
}
