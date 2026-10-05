import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/sync_monitor.dart';
import '../theme/app_colors.dart';

/// Thin strip above the bottom navigation: offline / syncing / all synced.
/// Hidden when online with nothing waiting, and on web (no [SyncMonitor]).
class SyncBanner extends StatelessWidget {
  const SyncBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final monitor = context.watch<SyncMonitor?>();
    if (monitor == null) return const SizedBox.shrink();

    final pending = monitor.pending;
    final (IconData icon, String text, Color color) = switch (monitor.state) {
      SyncState.idle => (Icons.cloud_done_outlined, '', Colors.transparent),
      SyncState.offline => (
          Icons.cloud_off_outlined,
          pending == 0
              ? 'Offline – showing saved data'
              : 'Offline – changes will sync ($pending pending)',
          AppColors.textSecondary,
        ),
      SyncState.syncing => (
          Icons.cloud_upload_outlined,
          'Syncing $pending ${pending == 1 ? 'change' : 'changes'}…',
          AppColors.primary,
        ),
      SyncState.synced => (
          Icons.cloud_done_outlined,
          'All changes synced',
          Colors.green.shade700,
        ),
    };

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      child: text.isEmpty
          ? const SizedBox(width: double.infinity)
          : Material(
              color: color,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    Icon(icon, size: 16, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        text,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
