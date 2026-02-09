/// Utility for parsing label files
///
/// Parses a .txt file where each line represents a class label.
/// Line 0 → class 0, Line 1 → class 1, etc.

/// Parse labels from file content
/// Returns a map of classId → label name
Map<int, String> parseLabelsFromContent(String content) {
  final lines = content.split('\n');
  final labels = <int, String>{};

  for (int i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isNotEmpty) {
      labels[i] = line;
    }
  }

  return labels;
}
