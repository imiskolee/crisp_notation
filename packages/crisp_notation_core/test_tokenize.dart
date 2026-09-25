import 'package:crisp_notation_core/crisp_notation_core.dart';

List<String> tokenize(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty) return const [];
  final hasCjk = trimmed.runes.any((r) =>
      (r >= 0x4e00 && r <= 0x9fff) ||
      (r >= 0x3000 && r <= 0x303f) ||
      (r >= 0x3040 && r <= 0x30ff) ||
      (r >= 0xac00 && r <= 0xd7af));
  if (hasCjk) {
    return trimmed.runes
        .map((r) => String.fromCharCode(r))
        .where((c) => !RegExp(r'[\s,，、;；。.!？：:·\-]').hasMatch(c))
        .toList();
  }
  return trimmed.split(RegExp(r'[\s,，、;；]+')).where((s) => s.isNotEmpty).toList();
}

void main() {
  final test = [
    "长亭外 古道边",
    "芳草碧连天",
    "晚风拂柳笛声残",
  ];
  for (final row in test) {
    final tokens = tokenize(row);
    print("$row → $tokens (${tokens.length})");
  }
}
