class SearchResult {
  final bool found;
  final String filename;
  final String linePreview;
  final int lineNumber;
  final double searchTimeMs;
  
  SearchResult({
    required this.found,
    required this.filename,
    required this.linePreview,
    required this.lineNumber,
    required this.searchTimeMs,
  });
}