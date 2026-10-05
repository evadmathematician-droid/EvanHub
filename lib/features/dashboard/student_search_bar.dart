import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/student_service.dart';
import '../../state/auth_controller.dart';
import '../../theme/app_colors.dart';
import '../students/student_details_screen.dart';

/// "Search student by ID…" on the dashboard. Looks the admission number up
/// in the signed-in user's own school only (offline too) and opens the
/// student's full record, or says plainly that there is no such student.
class StudentSearchBar extends StatefulWidget {
  const StudentSearchBar({super.key});

  @override
  State<StudentSearchBar> createState() => _StudentSearchBarState();
}

class _StudentSearchBarState extends State<StudentSearchBar> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    // Shows / hides the clear button as the user types.
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final input = _controller.text.trim();
    if (input.isEmpty || _busy) return;
    _focus.unfocus();
    setState(() {
      _busy = true;
      _message = null;
    });
    final service = StudentService(context.read<AuthController>().tenant!);
    try {
      final student = await service.findByAdmissionNo(input);
      if (!mounted) return;
      if (student == null) {
        setState(
            () => _message = 'No student found with ID $input in this school.');
        return;
      }
      await showStudentDetails(context, student);
    } on TimeoutException {
      if (mounted) {
        setState(() => _message = 'The student list is not saved on this '
            'phone yet. Connect to the internet once and try again.');
      }
    } catch (e) {
      debugPrint('Student search failed: $e');
      if (mounted) setState(() => _message = 'Search failed. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _clear() {
    _controller.clear();
    setState(() => _message = null);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.10),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: TextField(
            controller: _controller,
            focusNode: _focus,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: 'Search student by ID…',
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide:
                    const BorderSide(color: AppColors.primaryLight, width: 1.5),
              ),
              prefixIcon: _busy
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      tooltip: 'Search',
                      icon: const Icon(Icons.search,
                          color: AppColors.primary),
                      onPressed: _search,
                    ),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.close),
                      onPressed: _clear,
                    ),
            ),
          ),
        ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    size: 18, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(_message!,
                      style: const TextStyle(color: AppColors.textSecondary)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
