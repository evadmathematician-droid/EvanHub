import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/image_url.dart';
import '../../core/internet_check.dart';
import '../../models/school.dart';
import '../../services/cloudinary_service.dart';
import '../../services/export/export_images.dart';
import '../../services/school_service.dart';
import '../../state/auth_controller.dart';
import '../../theme/app_colors.dart';
import '../../widgets/status_views.dart';

/// Title of the screen that asks for the badge, motto and year founded.
const reportCardProfileTitle = 'Complete School Profile for Report Cards';

const _mottoMaxLength = 150;

/// Why [text] is not a usable year founded, or null when it is: four
/// digits, from 1800 to this year.
String? foundedYearProblem(String text, {DateTime? now}) {
  final t = text.trim();
  if (t.isEmpty) return 'Enter the year the school was founded.';
  if (!RegExp(r'^\d{4}$').hasMatch(t)) return 'Enter a 4-digit year.';
  final year = int.parse(t);
  final thisYear = (now ?? DateTime.now()).year;
  if (year < 1800 || year > thisYear) {
    return 'Enter a year from 1800 to $thisYear.';
  }
  return null;
}

/// Whether [meta] has everything report card covers need: the school
/// badge, the motto and a valid year founded.
bool hasReportCardProfile(SchoolMeta meta) =>
    (meta.logoUrl?.trim().isNotEmpty ?? false) &&
    meta.motto.trim().isNotEmpty &&
    meta.foundedYear != null &&
    foundedYearProblem('${meta.foundedYear}') == null;

/// Report Cards → edit school details: the same form as the gate, opened
/// from the level chooser to change the badge, motto or year later.
class ReportCardProfileScreen extends StatefulWidget {
  const ReportCardProfileScreen({super.key});

  @override
  State<ReportCardProfileScreen> createState() =>
      _ReportCardProfileScreenState();
}

class _ReportCardProfileScreenState extends State<ReportCardProfileScreen> {
  // Always the signed-in user's own school.
  late final Stream<School> _school =
      SchoolService().streamSchool(context.read<AuthController>().schoolId!);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Report Card Details')),
      body: StreamBuilder<School>(
        stream: _school,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorView(message: '${snapshot.error}');
          }
          if (!snapshot.hasData) return const LoadingView();
          return ReportCardProfileForm(
            school: snapshot.data!,
            onSaved: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Report card details saved.')));
              Navigator.of(context).maybePop();
            },
          );
        },
      ),
    );
  }
}

/// School badge (with preview), motto and year founded, validated and
/// saved to this school's own profile. Admins only; anyone else is asked to
/// contact their school admin.
class ReportCardProfileForm extends StatefulWidget {
  const ReportCardProfileForm({
    super.key,
    required this.school,
    required this.onSaved,
    this.intro,
  });

  final School school;
  final VoidCallback onSaved;

  /// Shown above the form (the gate explains why it appeared).
  final String? intro;

  @override
  State<ReportCardProfileForm> createState() => _ReportCardProfileFormState();
}

class _ReportCardProfileFormState extends State<ReportCardProfileForm> {
  final _form = GlobalKey<FormState>();
  late final _motto = TextEditingController(text: widget.school.meta.motto);
  late final _year = TextEditingController(
      text: widget.school.meta.foundedYear?.toString() ?? '');

  /// A newly picked badge, not uploaded yet.
  Uint8List? _pickedBytes;
  String _pickedName = '';
  bool _busy = false;
  bool _showLogoError = false;
  String? _message;

  String? get _savedLogoUrl {
    final url = widget.school.meta.logoUrl?.trim();
    return url == null || url.isEmpty ? null : url;
  }

  bool get _hasLogo => _pickedBytes != null || _savedLogoUrl != null;

  @override
  void dispose() {
    _motto.dispose();
    _year.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() {
      _pickedBytes = bytes;
      _pickedName = picked.name;
      _showLogoError = false;
      _message = null;
    });
  }

  Future<void> _save() async {
    final fieldsOk = _form.currentState!.validate();
    setState(() {
      _showLogoError = !_hasLogo;
      _message = null;
    });
    if (!fieldsOk || !_hasLogo) return;

    final schoolId = widget.school.id;
    final folder = context.read<AuthController>().tenant!.schoolProfileFolder;
    final service = SchoolService();
    setState(() => _busy = true);
    try {
      var logoUrl = _savedLogoUrl;
      if (_pickedBytes != null) {
        if (!await hasInternet()) {
          _say('Connect to the internet to upload the school badge.');
          return;
        }
        final upload = await CloudinaryService().upload(
          bytes: _pickedBytes!,
          fileName: _pickedName,
          folder: folder,
        );
        await service.setProfileImage(schoolId, 'logoUrl', upload.url);
        logoUrl = upload.url;
      }
      await service.setReportCardDetails(
        schoolId,
        motto: _motto.text,
        foundedYear: int.parse(_year.text.trim()),
      );
      // Keep the badge on the phone so report cards can print it offline.
      unawaited(ExportImages.load(ExportImages.badgeUrl(logoUrl)));
      if (!mounted) return;
      setState(() => _pickedBytes = null);
      widget.onSaved();
    } catch (e) {
      _say(_pickedBytes != null
          ? uploadFailedMessage(e)
          : 'Could not save. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _say(String message) {
    if (mounted) setState(() => _message = message);
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = context.watch<AuthController>().role.canManageSchool;
    final text = Theme.of(context).textTheme;
    if (!canEdit) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Report cards need the school badge, motto and year founded. '
            'Please ask your school admin to add them under More → Report '
            'Cards.',
            textAlign: TextAlign.center,
            style: text.bodyLarge,
          ),
        ),
      );
    }

    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.intro != null) ...[
            Text(widget.intro!,
                style: text.bodyMedium
                    ?.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 20),
          ],
          Text('School badge', style: text.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              _logoPreview(),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _pickLogo,
                      icon: const Icon(Icons.upload_outlined),
                      label: Text(_hasLogo ? 'Change badge' : 'Choose badge'),
                    ),
                    const SizedBox(height: 4),
                    Text('Printed on every report card cover. Needs internet '
                        'to upload.',
                        style: text.bodySmall
                            ?.copyWith(color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          if (_showLogoError) ...[
            const SizedBox(height: 6),
            Text('Choose the school badge.',
                style: text.bodySmall?.copyWith(color: AppColors.danger)),
          ],
          const SizedBox(height: 24),
          TextFormField(
            controller: _motto,
            enabled: !_busy,
            maxLength: _mottoMaxLength,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'School motto',
              hintText: 'e.g. Knowledge is power',
            ),
            validator: (v) => (v ?? '').trim().isEmpty
                ? 'Enter the school motto.'
                : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _year,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            decoration: const InputDecoration(
              labelText: 'Year founded',
              hintText: 'e.g. 1965',
            ),
            validator: (v) => foundedYearProblem(v ?? ''),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('Save'),
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(_message!, style: const TextStyle(color: AppColors.danger)),
          ],
        ],
      ),
    );
  }

  Widget _logoPreview() {
    final Widget image;
    if (_pickedBytes != null) {
      image = Image.memory(_pickedBytes!, fit: BoxFit.contain);
    } else if (_savedLogoUrl != null) {
      image = CachedNetworkImage(
        imageUrl: cloudinaryResized(_savedLogoUrl!, width: 300),
        fit: BoxFit.contain,
        errorWidget: (_, _, _) => const Icon(Icons.broken_image_outlined),
      );
    } else {
      image = const Center(
        child: Text('No badge',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
      );
    }
    return Container(
      width: 96,
      height: 96,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.background,
        shape: BoxShape.circle,
        border: Border.all(
            color: _showLogoError ? AppColors.danger : AppColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: image,
    );
  }
}
