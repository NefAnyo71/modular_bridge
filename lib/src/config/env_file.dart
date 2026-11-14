/// Zero-dependency `.env` / dotenv format parser.
///
/// Supports the common subset of dotenv syntax:
/// - `KEY=VALUE` pairs, one per line
/// - blank lines and `#` full-line comments
/// - optional `export ` prefix
/// - optional single or double quotes around values
/// - unquoted inline comments introduced by ` #`
library;

/// Parses dotenv content into a flat `Map<String, String>`.
///
/// Keys are trimmed and must be non-empty and contain no whitespace or `=`.
/// Values are trimmed; matching surrounding quotes are removed. For
/// unquoted values, an inline comment starting at the first ` #` (whitespace
/// followed by `#`) is stripped.
///
/// Throws a [FormatException] when a non-empty, non-comment line does not
/// contain an `=` separator or has an invalid key.
Map<String, String> parseEnvFile(String source) {
  final result = <String, String>{};
  final lines = source.split('\n');
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim();
    if (line.isEmpty || line.startsWith('#')) continue;

    if (line.startsWith('export ')) {
      line = line.substring('export '.length).trimLeft();
    }

    final eq = line.indexOf('=');
    if (eq <= 0) {
      throw FormatException(
        'Invalid dotenv line ${i + 1}: expected KEY=VALUE.',
        line,
      );
    }

    final key = line.substring(0, eq).trim();
    if (key.isEmpty || key.contains(' ') || key.contains('=')) {
      throw FormatException(
        'Invalid dotenv key on line ${i + 1}: "$key".',
        line,
      );
    }

    var value = line.substring(eq + 1).trim();
    if (value.length >= 2) {
      final first = value[0];
      final last = value[value.length - 1];
      if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
        value = value.substring(1, value.length - 1);
      } else {
        // Strip unquoted inline comments: whitespace followed by '#'.
        final commentIndex = _indexOfInlineComment(value);
        if (commentIndex >= 0) {
          value = value.substring(0, commentIndex).trimRight();
        }
      }
    } else if (value.isNotEmpty) {
      final commentIndex = _indexOfInlineComment(value);
      if (commentIndex >= 0) {
        value = value.substring(0, commentIndex).trimRight();
      }
    }

    result[key] = value;
  }
  return result;
}

int _indexOfInlineComment(String value) {
  for (var i = 0; i < value.length - 1; i++) {
    if (value[i] == ' ' && value[i + 1] == '#') return i;
    if (value[i] == '\t' && value[i + 1] == '#') return i;
  }
  return -1;
}
