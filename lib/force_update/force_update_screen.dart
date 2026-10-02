import 'package:flutter/material.dart';

/// Full-screen block shown instead of the whole app. It has no close, skip or
/// "later" control and no navigation: one button only — "Update Now" (or
/// "Try again" during maintenance). Back is blocked by `PopScope` here and by
/// `ForceUpdateGate`, which swallows the system Back event while blocked.
class ForceUpdateScreen extends StatelessWidget {
  const ForceUpdateScreen({
    super.key,
    required this.maintenance,
    required this.message,
    required this.installedVersion,
    required this.requiredVersionCode,
    required this.busy,
    required this.onPressed,
    this.logo,
    this.error,
  });

  /// Maintenance mode rather than an outdated build.
  final bool maintenance;
  final String message;

  /// e.g. "1.0.0 (1)".
  final String installedVersion;
  final int requiredVersionCode;
  final bool busy;
  final VoidCallback onPressed;
  final ImageProvider? logo;

  /// Shown under the button, e.g. when no update link could be opened.
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = maintenance ? 'Under maintenance' : 'Update required';
    final body = message.isNotEmpty
        ? message
        : maintenance
            ? 'The app is temporarily unavailable while we carry out '
                'maintenance. Please try again shortly.'
            : 'A new version of the app is available. This version is no '
                'longer supported — please update to continue.';

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (logo != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Image(
                          image: logo!,
                          width: 96,
                          height: 96,
                          fit: BoxFit.cover,
                        ),
                      )
                    else
                      Icon(
                        maintenance
                            ? Icons.build_circle_outlined
                            : Icons.system_update,
                        size: 96,
                        color: theme.colorScheme.primary,
                      ),
                    const SizedBox(height: 24),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      body,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge,
                    ),
                    if (!maintenance) ...[
                      const SizedBox(height: 20),
                      _VersionRow(
                        label: 'Installed version',
                        value: installedVersion,
                      ),
                      _VersionRow(
                        label: 'Required version',
                        value: 'build $requiredVersionCode or newer',
                      ),
                    ],
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: busy ? null : onPressed,
                        icon: busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(maintenance
                                ? Icons.refresh
                                : Icons.system_update_alt),
                        label: Text(maintenance ? 'Try again' : 'Update Now'),
                      ),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      // One wrapping paragraph, so large text on a narrow phone can't
      // overflow.
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: '$label: ', style: muted),
          TextSpan(
            text: value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ]),
        textAlign: TextAlign.center,
      ),
    );
  }
}
