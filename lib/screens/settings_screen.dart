import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/cache_provider.dart';
import '../providers/network_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final cacheProvider = context.watch<CacheProvider>();
    final networkProvider = context.watch<NetworkProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Cache Management Section
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Cache Management',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.storage),
                  title: const Text('Clear Cache'),
                  subtitle: const Text('Remove all cached data except downloads'),
                  onTap: _isLoading ? null : () => _clearCache(context),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_sweep),
                  title: const Text('Clear All Data'),
                  subtitle: const Text('Remove all cached data including downloads'),
                  onTap: _isLoading ? null : () => _clearAllData(context),
                ),
                ListTile(
                  leading: const Icon(Icons.sync),
                  title: const Text('Sync Library Now'),
                  subtitle: const Text('Force a full library sync'),
                  onTap: _isLoading ? null : () => _syncLibrary(context),
                ),
                if (networkProvider.isOffline)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.wifi_off, color: Colors.orange),
                        SizedBox(width: 8),
                        Text('Currently offline', style: TextStyle(color: Colors.orange)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Theme Section
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Appearance',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                // Theme mode switch would need to be implemented in ThemeProvider
                // const ListTile(
                //   leading: Icon(Icons.dark_mode),
                //   title: Text('Dark Mode'),
                //   trailing: Switch(
                //     value: false,
                //     onChanged: null,
                //   ),
                // ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // About Section
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'About',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                // Server version would need to be added to AuthProvider
                // const ListTile(
                //   leading: Icon(Icons.info),
                //   title: Text('Version'),
                //   subtitle: Text('Unknown'),
                // ),
                ListTile(
                  leading: const Icon(Icons.storage),
                  title: const Text('Database Path'),
                  subtitle: FutureBuilder<String>(
                    future: _getDatabasePath(),
                    builder: (context, snapshot) {
                      if (snapshot.hasData) {
                        return Text(
                          snapshot.data!,
                          style: Theme.of(context).textTheme.bodySmall,
                        );
                      }
                      return const Text('Loading...');
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<String> _getDatabasePath() async {
    // This would need to be implemented in DatabaseHelper
    return '/var/home/o/.local/share/dev.myyc.nhac/nhac.db';
  }

  Future<void> _clearCache(BuildContext context) async {
    final confirmed = await _showConfirmationDialog(
      context,
      'Clear Cache',
      'Are you sure you want to clear the cache? This will remove all cached cover art and metadata, but keep your downloaded songs.',
    );

    if (!confirmed) return;

    setState(() => _isLoading = true);

    try {
      final cacheProvider = context.read<CacheProvider>();
      await cacheProvider.clearCache();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cache cleared successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error clearing cache: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _clearAllData(BuildContext context) async {
    final confirmed = await _showConfirmationDialog(
      context,
      'Clear All Data',
      'Are you sure you want to clear all data? This will remove ALL cached data including downloaded songs. This action cannot be undone.',
    );

    if (!confirmed) return;

    setState(() => _isLoading = true);

    try {
      final cacheProvider = context.read<CacheProvider>();
      await cacheProvider.clearCache();
      // Note: You might want to add a method to clear downloads too

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All data cleared successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error clearing data: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _syncLibrary(BuildContext context) async {
    setState(() => _isLoading = true);

    try {
      final cacheProvider = context.read<CacheProvider>();
      await cacheProvider.syncFullLibrary();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Library sync completed')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error syncing library: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<bool> _showConfirmationDialog(
    BuildContext context,
    String title,
    String message,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    return result ?? false;
  }
}