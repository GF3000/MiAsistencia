/// Player search bars only appear when there are more players than this.
const playerSearchThreshold = 10;

/// Lowercases [value] and strips common Spanish accents so that searches
/// like "jose" match "José".
String normalizeSearchText(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[áàäâã]'), 'a')
      .replaceAll(RegExp(r'[éèëê]'), 'e')
      .replaceAll(RegExp(r'[íìïî]'), 'i')
      .replaceAll(RegExp(r'[óòöôõ]'), 'o')
      .replaceAll(RegExp(r'[úùüû]'), 'u');
}

/// Whether [text] contains every word of [query], in any order, ignoring
/// case and accents. An empty query matches everything, so "garcia ana"
/// matches "Ana García".
bool matchesSearchQuery(String text, String query) {
  final terms = normalizeSearchText(
    query,
  ).split(RegExp(r'\s+')).where((term) => term.isNotEmpty);
  final normalizedText = normalizeSearchText(text);
  return terms.every(normalizedText.contains);
}
