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

  const SchoolMeta({
    required this.name,
    this.logoUrl,
    this.coverUrl,
    this.address = '',
    this.phone = '',
    this.email = '',
  });

  factory SchoolMeta.fromMap(Map<String, dynamic> map) => SchoolMeta(
        name: (map['name'] ?? '') as String,
        logoUrl: map['logoUrl'] as String?,
        coverUrl: map['coverUrl'] as String?,
        address: (map['address'] ?? '') as String,
        phone: (map['phone'] ?? '') as String,
        email: (map['email'] ?? '') as String,
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'logoUrl': logoUrl,
        'coverUrl': coverUrl,
        'address': address,
        'phone': phone,
        'email': email,
      };

  SchoolMeta copyWith({
    String? name,
    String? logoUrl,
    String? coverUrl,
    String? address,
    String? phone,
    String? email,
  }) =>
      SchoolMeta(
        name: name ?? this.name,
        logoUrl: logoUrl ?? this.logoUrl,
        coverUrl: coverUrl ?? this.coverUrl,
        address: address ?? this.address,
        phone: phone ?? this.phone,
        email: email ?? this.email,
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
