import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/anisette_service.dart';
import '../state/app_state.dart';
import 'login_screen.dart';

/// App settings screen.
///
/// Allows the user to configure the Anisette server URL, log out, and view
/// project information.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _anisetteController;
  List<AnisetteServerSuggestion>? _suggestions;
  bool _loadingSuggestions = false;
  bool _testingServer = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    _anisetteController =
        TextEditingController(text: appState.anisetteServerUrl);
    _loadSuggestions();
  }

  @override
  void dispose() {
    _anisetteController.dispose();
    super.dispose();
  }

  Future<void> _loadSuggestions() async {
    setState(() => _loadingSuggestions = true);
    try {
      final suggestions =
          await AnisetteService().fetchServerSuggestions();
      if (!mounted) return;
      setState(() => _suggestions = suggestions);
    } catch (e) {
      // Suggestions are optional – keep the UI graceful but log for debugging.
      assert(() {
        // ignore: avoid_print
        print('[SettingsScreen] Failed to load Anisette server suggestions: $e');
        return true;
      }());
    } finally {
      if (mounted) setState(() => _loadingSuggestions = false);
    }
  }

  Future<void> _testServer() async {
    setState(() {
      _testingServer = true;
      _testResult = null;
    });
    final ok = await AnisetteService()
        .testServer(_anisetteController.text.trim());
    if (!mounted) return;
    setState(() {
      _testingServer = false;
      _testResult = ok ? '✅ Server reachable' : '❌ Server unreachable';
    });
  }

  void _saveAnisetteUrl() {
    final appState = context.read<AppState>();
    appState.setAnisetteServerUrl(_anisetteController.text.trim());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Anisette server URL saved')),
    );
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content:
            const Text('Are you sure you want to sign out? Your imported beacons will be cleared.'),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          FilledButton(
            child: const Text('Sign Out'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await context.read<AppState>().logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Account section
          Text('Account', style: theme.textTheme.labelLarge),
          Card(
            child: ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: const Text('Apple ID'),
              subtitle: Text(appState.currentUser?.email ?? 'Not signed in'),
              trailing: TextButton(
                onPressed: _logout,
                child: const Text('Sign Out'),
              ),
            ),
          ),

          const SizedBox(height: 16),
          Text('Anisette Server', style: theme.textTheme.labelLarge),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _anisetteController,
                    decoration: const InputDecoration(
                      labelText: 'Anisette Server URL',
                      border: OutlineInputBorder(),
                      helperText:
                          'Required to authenticate with Apple\'s servers.',
                    ),
                    keyboardType: TextInputType.url,
                  ),
                  if (_loadingSuggestions)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: LinearProgressIndicator(),
                    ),
                  if (_suggestions != null && _suggestions!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      children: _suggestions!.map((s) {
                        return ActionChip(
                          label: Text(s.name),
                          onPressed: () {
                            _anisetteController.text = s.url;
                          },
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (_testResult != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(_testResult!),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: _testingServer
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : const Icon(Icons.network_check),
                          label: const Text('Test'),
                          onPressed:
                              _testingServer ? null : _testServer,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Save'),
                          onPressed: _saveAnisetteUrl,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),
          Text('About', style: theme.textTheme.labelLarge),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('OpenTagViewer'),
                  subtitle: const Text('Flutter / Dart version'),
                ),
                ListTile(
                  leading: const Icon(Icons.open_in_new),
                  title: const Text('GitHub'),
                  subtitle: const Text(
                      'https://github.com/parawanderer/OpenTagViewer'),
                  onTap: () {
                    // URL launcher integration would open the URL here.
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              'https://github.com/parawanderer/OpenTagViewer')),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.menu_book_outlined),
                  title: const Text('Wiki'),
                  subtitle: const Text(
                      'https://github.com/parawanderer/OpenTagViewer/wiki'),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              'https://github.com/parawanderer/OpenTagViewer/wiki')),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
