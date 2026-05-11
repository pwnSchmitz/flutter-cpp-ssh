class TerminalCleaner {
  static String cleanOutput(String raw, String lastSentCommand) {
    String text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    
    List<String> lines = text.split('\n');
    List<String> processedLines = [];
    
    for (var line in lines) {
      if (lastSentCommand.isNotEmpty) {
        if (line.trim() == lastSentCommand) continue;
        if (line.trim() == '$lastSentCommand ') continue; // ✅ Интерполяция вместо конкатенации
        if (line.contains(lastSentCommand) && 
            RegExp(r'[\$#]\s*' + RegExp.escape(lastSentCommand)).hasMatch(line)) { // ✅ Добавлены фигурные скобки
          continue;
        }
      }
      
      if (RegExp(r'^[\w\-\.]+@[\w\-\.]+:[^$#]*[#$]\s*\$').hasMatch(line.trim())) continue;
      
      String processed = _processLineEdits(line);
      processedLines.add(processed);
    }
    
    String cleaned = processedLines.join('\n');
    cleaned = _stripAnsiCodes(cleaned);
    cleaned = _filterArtifactLines(cleaned);
    
    return cleaned;
  }

  static String _processLineEdits(String line) {
    List<String> buffer = [];
    for (int i = 0; i < line.length; i++) {
      String char = line[i];
      if (char == '\b') {
        if (buffer.isNotEmpty) buffer.removeLast();
      } else if (char == '\r') {
        buffer.clear();
      } else {
        buffer.add(char);
      }
    }
    return buffer.join();
  }

  static String _stripAnsiCodes(String text) {
    return text
        .replaceAll(RegExp(r'\x1B\[[0-9;?]*[a-zA-Z]'), '')
        .replaceAll(RegExp(r'\x1B\][0-9]+;[^\x07\x1B]*(\x07|\x1B\\\\)'), '')
        .replaceAll(RegExp(r'\x1B\][0-9]*;[^\x07]*\x07'), '')
        .replaceAll(RegExp(r'\x1B\([a-zA-Z0-9]'), '')
        .replaceAll(RegExp(r'\x1B[@-Z\\\\-_]'), '')
        .replaceAll('\x1B', '')
        .replaceAll(RegExp(r'[\x07]'), '');
  }

  static String _filterArtifactLines(String text) {
    List<String> lines = text.split('\n');
    List<String> filtered = [];
    
    for (String line in lines) {
      String t = line.trim();
      if (t.isEmpty) continue;
      
      if (t.startsWith('┌──') || t.startsWith('└─')) continue;
      if (t.contains('㉿') || (t.contains('@') && t.contains('[') && t.contains(']'))) continue;
      if (RegExp(r'^[\w\-\.]+@[\w\-\.]+:[^$#]*[#$]\s*').hasMatch(t)) continue;
      
      if (RegExp(r'^[a-zA-Z]{2,}[>\/]\s*\S').hasMatch(t)) continue;
      if (RegExp(r'^[a-zA-Z]{2,}[>\/]\$').hasMatch(t)) continue;
      
      if (RegExp(r'^[0-9]+;.*[@>]').hasMatch(t)) continue;
      if (t.startsWith(']0;')) continue;
      if (RegExp(r'^[0-9;]+\$').hasMatch(t)) continue;
      
      if (t.contains('dbus') && t.contains('machineid')) continue;
      if (t.contains('start=') && t.contains('pid=')) continue;
      if (t.startsWith('3008;')) continue;
      if (t.contains('journal') || t.contains('systemd')) continue;
      if (t.contains('type=command') && t.contains('cwd=')) continue;
      
      filtered.add(line);
    }
    return filtered.join('\n');
  }
}