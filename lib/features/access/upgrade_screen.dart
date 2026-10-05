import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/migration_service.dart';
import '../../state/auth_controller.dart';
import '../../theme/app_colors.dart';
import '../../widgets/sign_out_dialog.dart';

import 'gate_layout.dart';

/// Shown while the school still uses the pre-Phase-1 data layout. A school
/// admin checks the data, then runs the one-time migration; everyone else
/// waits.
class UpgradeScreen extends StatefulWidget {
  const UpgradeScreen({super.key});

  @override
  State<UpgradeScreen> createState() => _UpgradeScreenState();
}

class _UpgradeScreenState extends State<UpgradeScreen> {
  MigrationPlan? _plan;
  bool _busy = false;
  String? _error;

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _error = null;
      _plan = null;
    });
    try {
      final plan =
          await MigrationService(context.read<AuthController>().tenant!)
              .prepare();
      if (mounted) setState(() => _plan = plan);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not read the school data: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run() async {
    final plan = _plan;
    if (plan == null || !plan.ready) return;
    final auth = context.read<AuthController>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await MigrationService(auth.tenant!).run(plan);
      await auth.recheckSchool(); // Router moves on to the dashboard.
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'The update was rejected and nothing was '
            'changed. Check the data again. ($e)');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthController>();
    if (!auth.isAdmin) {
      return GateLayout(
        icon: Icons.hourglass_top,
        title: 'Your school is being upgraded',
        message: 'A school administrator needs to finish a one-time update of '
            'the school data. Please try again later.',
        children: [
          ElevatedButton.icon(
            onPressed: auth.recheckSchool,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => confirmSignOut(context),
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
        ],
      );
    }

    final plan = _plan;
    return GateLayout(
      icon: Icons.system_update_alt,
      title: 'Update school data',
      message: 'EvanHub now keeps private details (dates of birth, '
          'guardian contacts, exam records, teacher NINs …) in protected '
          'sections. This one-time update moves your existing records there. '
          'It is all-or-nothing: if anything fails, nothing is changed.\n\n'
          'Before you start, export a backup from the Firebase console '
          '(Realtime Database → ⋮ → Export JSON).',
      children: [
        if (plan == null)
          ElevatedButton.icon(
            onPressed: _busy ? null : _check,
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Check data'),
          )
        else if (!plan.ready) ...[
          Text('${plan.problems.length} problem(s) must be fixed first:',
              style: const TextStyle(
                  color: AppColors.danger, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final p in plan.problems)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('• $p'),
            ),
          const SizedBox(height: 8),
          const Text(
            'Fix these records in the Firebase console (Realtime Database → '
            'Data), then check again.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _check,
            icon: const Icon(Icons.refresh),
            label: const Text('Check again'),
          ),
        ] else ...[
          Text(
            'Ready: ${plan.students} student(s) and ${plan.teachers} '
            'teacher(s) will be moved.'
            '${plan.unassigned == 0 ? '' : ' ${plan.unassigned} student(s) '
                'point at a deleted class and will become unassigned.'}',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _busy ? null : _run,
            icon: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.play_arrow),
            label: const Text('Update school data'),
          ),
        ],
        if (_busy && plan == null) ...[
          const SizedBox(height: 16),
          const Center(child: CircularProgressIndicator()),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: AppColors.danger)),
        ],
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: () => confirmSignOut(context),
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
      ],
    );
  }
}
