import '../core/phone.dart';
import '../core/rtdb.dart';

/// School identity block — stored at `schools/{schoolId}/profile` (it lived at
/// `meta` before Phase 1). Readable by every member; admins write it.
class SchoolMeta {
  final String name;

  /// The school badge / crest (small round image).
  final String? logoUrl;

  /// The wide school photo shown at the top of the dashboard.
  final String? coverUrl;
  final String address;
  final String phone;
  final String email;

  /// The school stamp, printed on student record PDFs (ideally a PNG with a
  /// transparent background). Null or empty when none is uploaded.
  final String? stampUrl;

  /// Head Teacher / Principal, printed under the signature line.
  final String headName;

  /// Whether the school lets pupils, parents and teachers look up their own
  /// records without signing in. Null = never decided (schools registered
  /// before Look Up), which counts as approved; see [lookupApproved].
  final bool? lookupEnabled;

  /// When and by whom (uid) the Look Up decision was last made.
  final DateTime? lookupConsentAt;
  final String lookupConsentBy;

  /// The school administrator, shown to people asking about a school that
  /// has not approved Look Up. [adminPhone] is required for new schools;
  /// [adminWhatsApp] only when it differs. Both are kept as typed; the
  /// international forms for links come from [normalizePhone].
  final String adminName;
  final String adminPhone;
  final String adminWhatsApp;

  const SchoolMeta({
    required this.name,
    this.logoUrl,
    this.coverUrl,
    this.address = '',
    this.phone = '',
    this.email = '',
    this.stampUrl,
    this.headName = '',
    this.lookupEnabled,
    this.lookupConsentAt,
    this.lookupConsentBy = '',
    this.adminName = '',
    this.adminPhone = '',
    this.adminWhatsApp = '',
  });

  /// Look Up is on unless the school switched it off.
  bool get lookupApproved => lookupEnabled ?? true;

  /// `+232…` for links, or '' when there is no usable number.
  String get adminPhoneIntl => normalizePhone(adminPhone) ?? '';
  String get adminWhatsAppIntl => normalizePhone(adminWhatsApp) ?? '';

  factory SchoolMeta.fromMap(Map<String, dynamic> map) => SchoolMeta(
        name: (map['name'] ?? '') as String,
        logoUrl: map['logoUrl'] as String?,
        coverUrl: map['coverUrl'] as String?,
        address: (map['address'] ?? '') as String,
        phone: (map['phone'] ?? '') as String,
        email: (map['email'] ?? '') as String,
        stampUrl: map['stampUrl'] as String?,
        headName: (map['headName'] ?? '') as String,
        lookupEnabled: map['lookupEnabled'] as bool?,
        lookupConsentAt: fromMillis(map['lookupConsentAt']),
        lookupConsentBy: (map['lookupConsentBy'] ?? '') as String,
        adminName: (map['adminName'] ?? '') as String,
        adminPhone: (map['adminPhone'] ?? '') as String,
        adminWhatsApp: (map['adminWhatsApp'] ?? '') as String,
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'logoUrl': logoUrl,
        'coverUrl': coverUrl,
        'address': address,
        'phone': phone,
        'email': email,
        'stampUrl': stampUrl,
        'headName': headName,
        'lookupEnabled': lookupEnabled,
        'lookupConsentAt': toMillis(lookupConsentAt),
        'lookupConsentBy': lookupConsentBy.isEmpty ? null : lookupConsentBy,
        'adminName': adminName,
        'adminPhone': adminPhone,
        'adminPhoneIntl': adminPhoneIntl,
        'adminWhatsApp': adminWhatsApp,
        'adminWhatsAppIntl': adminWhatsAppIntl,
      };

  SchoolMeta copyWith({
    String? name,
    String? logoUrl,
    String? coverUrl,
    String? address,
    String? phone,
    String? email,
    String? stampUrl,
    String? headName,
    bool? lookupEnabled,
    DateTime? lookupConsentAt,
    String? lookupConsentBy,
    String? adminName,
    String? adminPhone,
    String? adminWhatsApp,
  }) =>
      SchoolMeta(
        name: name ?? this.name,
        logoUrl: logoUrl ?? this.logoUrl,
        coverUrl: coverUrl ?? this.coverUrl,
        address: address ?? this.address,
        phone: phone ?? this.phone,
        email: email ?? this.email,
        stampUrl: stampUrl ?? this.stampUrl,
        headName: headName ?? this.headName,
        lookupEnabled: lookupEnabled ?? this.lookupEnabled,
        lookupConsentAt: lookupConsentAt ?? this.lookupConsentAt,
        lookupConsentBy: lookupConsentBy ?? this.lookupConsentBy,
        adminName: adminName ?? this.adminName,
        adminPhone: adminPhone ?? this.adminPhone,
        adminWhatsApp: adminWhatsApp ?? this.adminWhatsApp,
      );
}

/// Subscription / account status — stored as the `subscription` map on
/// `schools/{schoolId}`.
class Subscription {
  final String plan; // free | standard | premium
  final String status; // trialing | active | past_due | canceled
  final DateTime? trialEndsAt;

  const Subscription({
    this.plan = 'free',
    this.status = 'trialing',
    this.trialEndsAt,
  });

  factory Subscription.fromMap(Map<String, dynamic> map) => Subscription(
        plan: (map['plan'] ?? 'free') as String,
        status: (map['status'] ?? 'trialing') as String,
        trialEndsAt: fromMillis(map['trialEndsAt']),
      );

  Map<String, dynamic> toMap() => {
        'plan': plan,
        'status': status,
        'trialEndsAt':
            toMillis(trialEndsAt),
      };
}

/// A school as the app shows it: its `profile` and `subscription`. The school
/// node itself isn't readable as a whole, so these are loaded separately
/// (see `SchoolService.streamSchool`).
class School {
  final String id;
  final SchoolMeta meta;
  final Subscription subscription;

  const School({
    required this.id,
    required this.meta,
    this.subscription = const Subscription(),
  });
}
