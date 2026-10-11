import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/public_lookup_service.dart';
import '../../theme/app_colors.dart';

/// Shown instead of a record when [school] has not approved Look Up: no
/// record is read. Offers the administrator's number with Call and
/// WhatsApp, or asks people to contact the school directly.
Future<void> showLookupNotApproved(BuildContext context, PublicSchool school) =>
    showDialog<void>(
      context: context,
      builder: (_) => _LookupNotApprovedDialog(school: school),
    );

class _LookupNotApprovedDialog extends StatelessWidget {
  const _LookupNotApprovedDialog({required this.school});

  final PublicSchool school;

  Future<void> _call(BuildContext context) async {
    final ok = await _open(Uri(scheme: 'tel', path: school.adminPhone));
    if (!ok && context.mounted) _snack(context, 'Could not open the phone app.');
  }

  Future<void> _whatsApp(BuildContext context) async {
    final number = school.whatsAppNumber.replaceFirst('+', '');
    final text = 'Hello, I am trying to check a record for ${school.name} on '
        'the Evangelist Global app. Please can you help me / turn on Lookup?';
    final ok = await _open(Uri.https('wa.me', '/$number', {'text': text}));
    if (!ok && context.mounted) _snack(context, 'WhatsApp not available.');
  }

  static Future<bool> _open(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Could not open $uri: $e');
      return false;
    }
  }

  static void _snack(BuildContext context, String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final hasPhone = school.adminPhone.isNotEmpty;
    final hasWhatsApp = school.whatsAppNumber.isNotEmpty;
    return AlertDialog(
      icon: const Icon(Icons.lock_clock_outlined,
          color: AppColors.warning, size: 40),
      title: const Text('Lookup not yet approved'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: school.name,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const TextSpan(
                  text: ' is registered on Evangelist Global, but the school '
                      'has not yet given permission for its records to be '
                      'shown through Lookup. Please contact the school '
                      'administration to get your information or to ask them '
                      'to turn on Lookup.'),
            ]),
          ),
          const SizedBox(height: 16),
          if (hasPhone) ...[
            Text(
              school.adminName.isEmpty
                  ? 'School administrator'
                  : 'School administrator: ${school.adminName}',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 4),
            SelectableText(school.adminPhone,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700)),
            if (school.adminWhatsApp.isNotEmpty &&
                school.adminWhatsApp != school.adminPhone) ...[
              const SizedBox(height: 2),
              SelectableText('WhatsApp: ${school.adminWhatsApp}',
                  style: const TextStyle(color: AppColors.textSecondary)),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _call(context),
                    icon: const Icon(Icons.call),
                    label: const Text('Call'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366)),
                    onPressed: hasWhatsApp ? () => _whatsApp(context) : null,
                    icon: const Icon(Icons.chat),
                    label: const Text('WhatsApp'),
                  ),
                ),
              ],
            ),
          ] else
            const Text('Please visit or contact the school directly.',
                style: TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
