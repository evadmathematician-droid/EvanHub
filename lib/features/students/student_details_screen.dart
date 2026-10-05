import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/offline_write.dart';
import '../../core/rtdb.dart';
import '../../models/promotion_record.dart';
import '../../models/school.dart';
import '../../models/student.dart';
import '../../services/export/export_images.dart';
import '../../services/export/student_record_export.dart';
import '../../services/export/student_record_pdf.dart';
import '../../services/promotion_service.dart';
import '../../services/upload_queue.dart';
import '../../state/auth_controller.dart';
import '../../theme/app_colors.dart';
import '../../widgets/photo_avatar.dart';
import '../../widgets/repeater_badge.dart';

/// Opens [student]'s full record: a full-screen page on phones, a large
/// centred dialog (up to 900 px wide, scrollable) on web and wide screens.
/// [student] must have its private half loaded.
Future<void> showStudentDetails(BuildContext context, Student student) {
  final wide = kIsWeb || MediaQuery.sizeOf(context).width >= 700;
  if (!wide) {
    return Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => StudentDetailsScreen(student: student),
    ));
  }
  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: StudentDetailsScreen(student: student),
      ),
    ),
  );
}

/// What a promotion record means: no target class = Graduated, same class =
/// Repeated, anything else = Promoted.
String promotionOutcome(PromotionRecord r) => r.toClassId.isEmpty
    ? 'Graduated'
    : r.toClassId == r.fromClassId
        ? 'Repeated'
        : 'Promoted';

/// Everything recorded about one student, in cards: personal, guardian,
/// academic, exam records and promotion history.
class StudentDetailsScreen extends StatefulWidget {
  const StudentDetailsScreen({super.key, required this.student});

  final Student student;

  @override
  State<StudentDetailsScreen> createState() => _StudentDetailsScreenState();
}

/// Class names plus promotion history, loaded after the page opens.
class _Extras {
  const _Extras(this.classNames, this.history);

  final Map<String, String> classNames;

  /// Null when this user may not read promotion history (teachers).
  final List<PromotionRecord>? history;
}

class _StudentDetailsScreenState extends State<StudentDetailsScreen> {
  late final Future<_Extras> _extras;

  static final _date = DateFormat('d MMM yyyy');

  @override
  void initState() {
    super.initState();
    _extras = _loadExtras();
    // So a later export works offline.
    ExportImages.prefetch([ExportImages.photoUrl(widget.student.photoUrl)]);
  }

  bool _exporting = false;

  String _className(String? id, _Extras? extras) {
    if (id == null || id.isEmpty) return 'Not assigned';
    if (extras == null) return '…';
    return extras.classNames[id] ?? 'Deleted class';
  }

  Future<void> _chooseExport() async {
    // Phones share through the system sheet; the web can only share in some
    // browsers, so it says "download" where that is what happens.
    final choice =
        await showModalBottomSheet<(RecordFormat, RecordAction)>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.share_outlined,
                  color: AppColors.primary),
              title: const Text('Share PDF'),
              subtitle: Text(kIsWeb
                  ? 'Share from the browser, or download if it can\'t'
                  : 'WhatsApp, Telegram, Gmail, Bluetooth, Drive …'),
              onTap: () => Navigator.pop(
                  context, (RecordFormat.pdf, RecordAction.share)),
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined,
                  color: AppColors.danger),
              title: Text(kIsWeb ? 'Download PDF' : 'Save PDF to device'),
              subtitle: const Text('A4 record with school letterhead'),
              onTap: () => Navigator.pop(
                  context, (RecordFormat.pdf, RecordAction.save)),
            ),
            ListTile(
              leading:
                  const Icon(Icons.image_outlined, color: AppColors.info),
              title: const Text('Share as image'),
              subtitle: const Text('The same record as a PNG picture'),
              onTap: () => Navigator.pop(
                  context, (RecordFormat.png, RecordAction.share)),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice != null) await _export(choice.$1, choice.$2);
  }

  /// "Preparing document…" over the page while the record is built.
  void _showPreparing() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              SizedBox(width: 16),
              Text('Preparing document…'),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the record from what is on the phone (works offline), always
  /// with the signed-in user's own school, then shares or saves it.
  Future<void> _export(RecordFormat format, RecordAction action) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context, rootNavigator: true);
    final refs = context.read<AuthController>().tenant!;
    final s = widget.student;
    setState(() => _exporting = true);
    _showPreparing();
    var preparing = true;
    void closePreparing() {
      if (preparing) navigator.pop();
      preparing = false;
    }

    try {
      final extras = await _extras;
      final profile = asMap((await readOnce(refs.profile)).value);
      final meta = SchoolMeta.fromMap(profile);
      // Images still waiting to upload are taken straight from the phone.
      final queue = UploadQueue.instance;
      final localPhoto = queue?.localPhoto(s.id);
      final localStamp =
          queue?.localSchoolImage(refs.schoolId, 'profile', 'stampUrl');
      final images = await Future.wait([
        ExportImages.load(ExportImages.badgeUrl(meta.logoUrl)),
        localPhoto != null
            ? File(localPhoto).readAsBytes()
            : ExportImages.load(ExportImages.photoUrl(s.photoUrl)),
        localStamp != null
            ? File(localStamp).readAsBytes()
            : ExportImages.load(ExportImages.stampUrl(meta.stampUrl)),
      ]);
      final history = extras.history;
      final data = StudentRecordData(
        student: s,
        className: _className(s.classId, extras),
        historyVisible: history != null,
        history: [
          for (final r in history ?? const <PromotionRecord>[])
            HistoryLine(
              year: r.academicYear,
              from: _className(r.fromClassId, extras),
              to: r.toClassId.isEmpty ? '' : _className(r.toClassId, extras),
              outcome: promotionOutcome(r),
              date: r.promotedAt == null ? '' : _date.format(r.promotedAt!),
            ),
        ],
        schoolId: refs.schoolId,
        schoolName: meta.name,
        schoolAddress: meta.address,
        schoolPhone: meta.phone,
        schoolEmail: meta.email,
        // The app has no motto field yet; printed only if one is on the
        // school profile.
        motto: (profile['motto'] ?? '').toString(),
        headName: meta.headName,
        badge: images[0],
        photo: images[1],
        stamp: images[2],
        exportedAt: DateTime.now(),
      );
      final bytes = await StudentRecordExport.build(data, format);
      closePreparing();
      final name = StudentRecordExport.fileName(s, format);
      final done =
          await StudentRecordExport.deliver(name, bytes, format, action);
      if (done && action == RecordAction.save) {
        messenger.showSnackBar(SnackBar(
            content: Text(kIsWeb ? 'Downloaded $name' : 'Saved $name')));
      }
    } catch (e) {
      debugPrint('Student export failed: $e');
      messenger.showSnackBar(
          const SnackBar(content: Text('Could not export. Please try again.')));
    } finally {
      closePreparing();
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Read from the phone's copy, so this works offline. A failure only hides
  /// class names / history; the record itself is already on screen.
  Future<_Extras> _loadExtras() async {
    final auth = context.read<AuthController>();
    final refs = auth.tenant!;
    final names = <String, String>{};
    try {
      for (final c in (await readOnce(refs.classes)).children) {
        if (c.key != null) names[c.key!] = (asMap(c.value)['name'] ?? '').toString();
      }
    } catch (e) {
      debugPrint('Class names unavailable: $e');
    }
    List<PromotionRecord>? history;
    if (auth.isAdmin) {
      try {
        history = await PromotionService(refs).history(widget.student.id);
      } catch (e) {
        debugPrint('Promotion history unavailable: $e');
        history = const [];
      }
    }
    return _Extras(names, history);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.student;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Student details'),
        actions: [
          if (_exporting)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton.icon(
              onPressed: _chooseExport,
              icon: const Icon(Icons.ios_share),
              label: const Text('Export'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: FutureBuilder<_Extras>(
        future: _extras,
        builder: (context, snapshot) {
          final extras = snapshot.data;
          String className(String? id) => _className(id, extras);

          final sections = <Widget>[
            _Section(
              title: 'Personal information',
              icon: Icons.person_outline,
              rows: [
                ('Full name', s.fullName),
                ('First name', s.firstName),
                ('Middle name', s.middleName),
                ('Last name', s.lastName),
                ('Gender', _capitalise(s.gender)),
                ('Date of birth', _dob(s.dob)),
                ('Home address', s.address),
              ],
            ),
            _Section(
              title: 'Guardian / contact',
              icon: Icons.family_restroom_outlined,
              rows: [
                ('Guardian name', s.guardianName),
                ('Guardian phone', s.guardianPhone),
              ],
            ),
            _Section(
              title: 'Academic information',
              icon: Icons.school_outlined,
              rows: [
                ('Student ID', s.admissionNo),
                ('Level', s.level?.label ?? ''),
                ('Class', className(s.classId)),
                ('Department', s.department ?? ''),
                ('Admission year', s.admissionYear),
                ('Date registered', _fmt(s.createdAt)),
                ('Status', StudentStatus.label(s.status)),
                ('Last promoted', s.lastPromotedAt == null
                    ? 'Not yet promoted'
                    : _fmt(s.lastPromotedAt)),
              ],
            ),
            _Section(
              title: 'Exam records',
              icon: Icons.assignment_outlined,
              rows: [
                ('NPSE index no.', s.npseId),
                ('NPSE year', s.npseYear),
                ('BECE index no.', s.beceId),
                ('BECE year', s.beceYear),
                ('WASSCE index no.', s.wassceId),
                ('WASSCE year', s.wassceYear),
              ],
            ),
            _HistorySection(
              loading: extras == null,
              history: extras?.history,
              className: className,
            ),
          ];

          return LayoutBuilder(builder: (context, constraints) {
            // Two columns of cards when there is room (web, tablets).
            final twoColumns = constraints.maxWidth >= 700;
            final cardWidth = twoColumns
                ? (constraints.maxWidth - 16 * 2 - 12) / 2
                : constraints.maxWidth - 16 * 2;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _Header(student: s, className: className(s.classId)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final section in sections)
                      SizedBox(width: cardWidth, child: section),
                  ],
                ),
              ],
            );
          });
        },
      ),
    );
  }

  static String _fmt(DateTime? d) => d == null ? '' : _date.format(d);

  static String _dob(DateTime? d) {
    if (d == null) return '';
    final now = DateTime.now();
    var age = now.year - d.year;
    if (now.month < d.month || (now.month == d.month && now.day < d.day)) {
      age--;
    }
    return '${_date.format(d)}  ($age yrs)';
  }

  static String _capitalise(String s) =>
      s.isEmpty ? '' : s[0].toUpperCase() + s.substring(1);
}

class _Header extends StatelessWidget {
  const _Header({required this.student, required this.className});

  final Student student;
  final String className;

  @override
  Widget build(BuildContext context) {
    final s = student;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            PhotoAvatar(
              url: s.photoUrl,
              title: s.fullName,
              recordId: s.id,
              radius: 44,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.fullName,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text('ID: ${s.admissionNo.isEmpty ? '—' : s.admissionNo}',
                      style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600)),
                  Text(className,
                      style: const TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      StatusBadge(status: s.status),
                      if (s.isRepeater()) const RepeaterBadge(),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Coloured pill for a [StudentStatus].
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      StudentStatus.active => AppColors.success,
      StudentStatus.graduated => AppColors.info,
      StudentStatus.transferred => AppColors.warning,
      _ => AppColors.textMuted,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        StudentStatus.label(status),
        style: TextStyle(
            color: color, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// A titled card of label / value rows. Empty values show as "—" so every
/// field on the record is visible.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.icon, required this.rows});

  final String title;
  final IconData icon;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: title,
      icon: icon,
      children: [
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 130,
                  child: Text(label,
                      style: const TextStyle(color: AppColors.textSecondary)),
                ),
                Expanded(
                  child: Text(
                    value.trim().isEmpty ? '—' : value,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _HistorySection extends StatelessWidget {
  const _HistorySection({
    required this.loading,
    required this.history,
    required this.className,
  });

  final bool loading;
  final List<PromotionRecord>? history;
  final String Function(String?) className;

  static final _date = DateFormat('d MMM yyyy');

  @override
  Widget build(BuildContext context) {
    final list = history;
    final Widget body;
    if (loading) {
      body = const Text('Loading…',
          style: TextStyle(color: AppColors.textSecondary));
    } else if (list == null) {
      body = const Text('Promotion history is visible to school admins.',
          style: TextStyle(color: AppColors.textSecondary));
    } else if (list.isEmpty) {
      body = const Text('No promotions recorded yet.',
          style: TextStyle(color: AppColors.textSecondary));
    } else {
      body = Column(
        children: [
          for (final r in list) _row(r),
        ],
      );
    }
    return _Card(
      title: 'Promotion history',
      icon: Icons.trending_up,
      children: [body],
    );
  }

  Widget _row(PromotionRecord r) {
    final outcome = promotionOutcome(r);
    final color = switch (outcome) {
      'Graduated' => AppColors.info,
      'Repeated' => AppColors.danger,
      _ => AppColors.success,
    };
    final to = r.toClassId.isEmpty ? '' : ' → ${className(r.toClassId)}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(r.academicYear.isEmpty ? '—' : r.academicYear,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${className(r.fromClassId)}$to'),
                if (r.promotedAt != null)
                  Text(_date.format(r.promotedAt!),
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          Text(outcome,
              style: TextStyle(color: color, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
              ],
            ),
            const Divider(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }
}
