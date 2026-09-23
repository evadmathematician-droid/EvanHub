import 'package:firebase_database/firebase_database.dart';

/// Realtime Database returns nested `Map<Object?, Object?>` values; this deep-
/// converts them into `Map<String, dynamic>` so models can parse them normally.
Map<String, dynamic> asMap(Object? value) {
  if (value is! Map) return <String, dynamic>{};
  return value.map((k, v) => MapEntry(k.toString(), _convert(v)));
}

Object? _convert(Object? v) {
  if (v is Map) return asMap(v);
  if (v is List) return v.map(_convert).toList();
  return v;
}

/// Realtime Database has no Timestamp type — dates are stored as epoch millis
/// (`ServerValue.timestamp` for "now").
DateTime? fromMillis(Object? value) =>
    value is int ? DateTime.fromMillisecondsSinceEpoch(value) : null;

int? toMillis(DateTime? value) => value?.millisecondsSinceEpoch;

/// Streams every child of [ref] as a parsed list. Ordering is left to the caller
/// (sort in Dart) so no `.indexOn` rules are required.
Stream<List<T>> watchList<T>(
  DatabaseReference ref,
  T Function(String id, Map<String, dynamic> data) parse,
) {
  return ref.onValue.map((event) {
    final items = <T>[];
    for (final child in event.snapshot.children) {
      final key = child.key;
      if (key == null || child.value is! Map) continue;
      items.add(parse(key, asMap(child.value)));
    }
    return items;
  });
}

/// Key for `index/admissionNo/{key}`: lower-cased, with the characters a
/// database key can't hold (and `%` itself) percent-encoded. Must match the
/// normalisation in `database.rules.json`, which re-checks it.
String indexKey(String admissionNo) => admissionNo
    .trim()
    .toLowerCase()
    .replaceAll('%', '%25')
    .replaceAll('.', '%2e')
    .replaceAll('#', '%23')
    .replaceAll(r'$', '%24')
    .replaceAll('[', '%5b')
    .replaceAll(']', '%5d')
    .replaceAll('/', '%2f');

/// Case-insensitive string comparison used for name ordering.
int compareText(String a, String b) =>
    a.toLowerCase().compareTo(b.toLowerCase());
