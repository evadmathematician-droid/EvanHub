import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/image_url.dart';
import '../../models/lookup_record.dart';
import '../../models/student.dart';
import '../../models/teacher.dart';
import '../../theme/app_colors.dart';

/// Shows [record] as a pop-up, styled after the Bubuya app's look-up result:
/// round photo, name, ID and status badge, then the sections in order —
/// personal details and IDs, fees, promotion and position, results, remarks
/// and guidance. Empty fields and sections are left out.
Future<void> showLookupResult(
  BuildContext context, {
  required LookupRecord record,
  required String schoolName,
}) =>
    showDialog<void>(
      context: context,
      builder: (_) => LookupResultDialog(record: record, schoolName: schoolName),
    );

class LookupResultDialog extends StatelessWidget {
  const LookupResultDialog(
      {super.key, required this.record, required this.schoolName});

  final LookupRecord record;
  final String schoolName;

  static final _date = DateFormat('d MMM yyyy');

  String get _firstName =>
      record.firstName.trim().isEmpty ? 'This pupil' : record.firstName.trim();

  @override
  Widget build(BuildContext context) {
    final r = record;
    final sections = r.isStudent
        ? [
            _personal(),
            _fees(),
            _promotion(),
            _results(),
            _remarks(),
          ]
        : [_teacherDetails()];

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 460,
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close, color: AppColors.textSecondary),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: _Photo(url: r.photoUrl, name: r.fullName)),
                    const SizedBox(height: 10),
                    Text(r.fullName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      r.isStudent ? 'Student ID: ${r.id}' : 'Staff ID (NIN): ${r.id}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    if (schoolName.isNotEmpty)
                      Text(schoolName,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 12.5, color: AppColors.textMuted)),
                    const SizedBox(height: 8),
                    Center(child: _statusBadge()),
                    for (final s in sections) ?s,
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge() {
    final (String label, Color color) = record.isStudent
        ? switch (record.status) {
            StudentStatus.active => ('Registered', AppColors.success),
            StudentStatus.graduated => ('Completed school', AppColors.info),
            StudentStatus.transferred => ('Transferred', AppColors.textSecondary),
            _ => ('Past Student', AppColors.textSecondary),
          }
        : (TeacherStatus.label(record.status),
            TeacherStatus.normalize(record.status) == TeacherStatus.active
                ? AppColors.success
                : AppColors.textSecondary);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontWeight: FontWeight.w700, fontSize: 12.5)),
    );
  }

  // ---------------------------------------------------------- sections

  /// 1. Personal details and IDs.
  Widget? _personal() {
    final r = record;
    return _Section.of('Personal details and IDs', [
      _Field.of('Class', r.className),
      _Field.of('Level', r.levelLabel),
      _Field.of('Department', r.department),
      _Field.of('Gender', r.gender),
      _Field.of('Year admitted', r.admissionYear),
      _Field.of('Address', r.address),
      _Field.of('NPSE Number', _exam(r.npseId, r.npseYear)),
      _Field.of('BECE Number', _exam(r.beceId, r.beceYear)),
      _Field.of('WASSCE Index', _exam(r.wassceId, r.wassceYear)),
    ]);
  }

  /// "12345 — sat 2021", or just the number when the year is blank.
  static String _exam(String number, String year) {
    if (number.trim().isEmpty) return '';
    return year.trim().isEmpty ? number : '$number — sat $year';
  }

  /// 2. Fees: the balance large, red when money is owed, green when paid.
  Widget? _fees() {
    final f = LookupFees(record.fees);
    if (!f.hasAny) return null;
    final balance = f.balance;
    final paidUp = balance != null && balance <= 0;
    final color = paidUp ? AppColors.success : AppColors.danger;
    return _Section.of('School fees', [
      if (balance != null)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Column(
            children: [
              Text(paidUp ? 'Fees paid in full' : 'Balance to pay',
                  style: TextStyle(color: color, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(_money(paidUp ? 0 : balance),
                  style: TextStyle(
                      color: color,
                      fontSize: 26,
                      fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      _Field.of('Total fees', f.total == null ? '' : _money(f.total!)),
      _Field.of('Amount paid', f.paid == null ? '' : _money(f.paid!)),
      _Field.of('Payment status', f.paymentStatus),
      _Field.of('Last payment',
          f.lastPaymentAt == null ? '' : _date.format(f.lastPaymentAt!)),
    ]);
  }

  static String _money(num v) => 'Le ${NumberFormat('#,##0.##').format(v)}';

  /// 3. Promotion and position, with the history cards.
  Widget? _promotion() {
    final r = record;
    final status = r.promotionStatus();
    final position = LookupResults(r.results).positionText;
    return _Section.of('Promotion and position', [
      _Field.of('Promotion status', status),
      if (status == 'Promoted') _Field.of('Promoted to', r.className),
      _Field.of('Last promoted',
          r.lastPromotedAt == null ? '' : _date.format(r.lastPromotedAt!)),
      _Field.of('Position in class', position ?? ''),
      // Latest first, like Bubuya.
      for (final p in r.history.reversed) _HistoryCard(p, _firstName),
    ]);
  }

  /// 4. Results.
  Widget? _results() {
    final res = LookupResults(record.results);
    if (!res.hasAny) return null;
    String n(num? v) =>
        v == null ? '' : NumberFormat('#,##0.##').format(v);
    // Position is shown under "Promotion and position".
    return _Section.of('Results', [
      _Field.of('Total score', n(res.totalScore)),
      _Field.of('Average', res.average == null ? '' : '${n(res.average)}%'),
      if (res.subjects.isNotEmpty) ...[
        const Padding(
          padding: EdgeInsets.only(top: 6, bottom: 2),
          child: Text('Subject scores',
              style: TextStyle(fontWeight: FontWeight.w600)),
        ),
        for (final e in res.subjects.entries) ?_Field.of(e.key, n(e.value)),
      ],
    ]);
  }

  /// 5. Remarks and guidance: the school's remarks in full, or the automatic
  /// note when the school wrote none; then who to contact.
  Widget? _remarks() {
    final written = [
      for (final e in record.remarks.entries)
        if ('${e.value ?? ''}'.trim().isNotEmpty)
          (_remarkLabel(e.key), '${e.value}'.trim()),
    ];
    final auto = written.isEmpty
        ? LookupResults(record.results).automaticGuidance
        : null;
    return _Section.of('Remarks and guidance', [
      for (final (label, text) in written) _Remark(label, text),
      if (auto != null) _Remark('Guidance', auto),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          'For more information on $_firstName\'s performance, parents and '
          'guardians may contact the class teacher or the Principal.',
          style: const TextStyle(
              fontSize: 12.5, color: AppColors.textSecondary),
        ),
      ),
    ]);
  }

  static String _remarkLabel(String key) => switch (key) {
        'classTeacher' => 'Class teacher\'s remark',
        'headTeacher' => 'Head teacher\'s remark',
        'principal' => 'Principal\'s remark',
        'conduct' => 'Conduct',
        'position' || 'positionReason' => 'About the position',
        'advice' => 'Advice',
        'seeAdministration' => 'Message to parents',
        _ => key
            .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
            .replaceAll('_', ' ')
            .replaceFirstMapped(RegExp(r'^\w'), (m) => m[0]!.toUpperCase()),
      };

  /// Teachers: rank and teaching details.
  Widget? _teacherDetails() {
    final r = record;
    final level = switch (r.teachingLevel) {
      'JSS' => 'Junior secondary (JSS)',
      'SSS' => 'Senior secondary (SSS)',
      'BOTH' => 'JSS and SSS',
      final v => v,
    };
    return _Section.of('Personal details', [
      _Field.of('Rank', TeacherRank.label(r.rank)),
      _Field.of('Status', TeacherStatus.label(r.status)),
      _Field.of('Gender', r.gender),
      _Field.of('Subjects', r.subjects),
      _Field.of('Teaches', level),
      _Field.of('Stream', r.stream),
    ]);
  }
}

/// A titled block; null when it would be empty.
class _Section extends StatelessWidget {
  const _Section(this.title, this.children);

  final String title;
  final List<Widget> children;

  static Widget? of(String title, List<Widget?> children) {
    final shown = children.whereType<Widget>().toList();
    return shown.isEmpty ? null : _Section(title, shown);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary)),
          const Divider(height: 12),
          ...children,
        ],
      ),
    );
  }
}

/// "Label    value" on one line; null when the value is empty.
class _Field extends StatelessWidget {
  const _Field(this.label, this.value);

  final String label;
  final String value;

  static Widget? of(String label, String value) =>
      value.trim().isEmpty ? null : _Field(label, value.trim());

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

/// A remark shown in full.
class _Remark extends StatelessWidget {
  const _Remark(this.label, this.text);

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
                  const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(text, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}

/// One promotion entry, like Bubuya's: "JSS 1 → JSS 2", the year and date,
/// then one plain sentence.
class _HistoryCard extends StatelessWidget {
  const _HistoryCard(this.p, this.firstName);

  final LookupPromotion p;
  final String firstName;

  @override
  Widget build(BuildContext context) {
    final from = p.fromClass.isEmpty ? 'their class' : p.fromClass;
    final (String to, String sentence) = p.completed
        ? ('Completed', '$firstName has completed $from.')
        : p.repeated
            ? (p.toClass, '$firstName will repeat $from.')
            : (p.toClass, '$firstName was promoted from $from to ${p.toClass}.');
    final meta = [
      p.academicYear,
      if (p.date != null) LookupResultDialog._date.format(p.date!),
    ].where((s) => s.trim().isNotEmpty).join(' · ');
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE1E6F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$from → $to',
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          if (meta.isNotEmpty)
            Text(meta,
                style: const TextStyle(
                    fontSize: 11.5, color: AppColors.textMuted)),
          const SizedBox(height: 4),
          Text(sentence, style: const TextStyle(fontSize: 12.5)),
        ],
      ),
    );
  }
}

/// The photo, centred and cropped to fill a fixed circle (no stretching, no
/// white bars). Cloudinary photos are requested face-centred and square.
/// Initials when there is no photo or it can't load.
class _Photo extends StatelessWidget {
  const _Photo({required this.url, required this.name});

  final String url;
  final String name;

  static const _size = 120.0;

  @override
  Widget build(BuildContext context) {
    final initials = Container(
      color: AppColors.primary.withValues(alpha: 0.12),
      alignment: Alignment.center,
      child: Text(_initials(name),
          style: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w700,
              color: AppColors.primary)),
    );
    return ClipOval(
      child: SizedBox(
        width: _size,
        height: _size,
        child: url.trim().isEmpty
            ? initials
            : CachedNetworkImage(
                imageUrl: cloudinaryFaceCrop(url),
                fit: BoxFit.cover,
                alignment: Alignment.center,
                width: _size,
                height: _size,
                placeholder: (_, _) => initials,
                errorWidget: (_, _, _) => initials,
              ),
      ),
    );
  }

  static String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    final first = parts.first[0];
    final last = parts.length > 1 ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }
}
