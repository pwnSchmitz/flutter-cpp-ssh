import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/ssh_connection.dart';
import '../models/terminal_line.dart';

class TerminalLineBuilder {
  static Widget build(
    TerminalLine line, 
    bool isLastPrompt, 
    SSHConnection connection, 
    FocusNode focusNode,
    Color systemColor,
  ) {
    if (line.text.contains('${connection.username}@${connection.host}:~\$')) {
      final match = RegExp(r'[\$#]\s+(.+)\$').firstMatch(line.text);
      final cmd = match?.group(1) ?? line.text;
      
      return Padding(
        padding: const EdgeInsets.only(bottom: 2.0), 
        child: RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: "${connection.username}@${connection.host}:~\$ ", 
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 14, 
                  height: 1.4, 
                  color: Colors.greenAccent, 
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextSpan(
                text: cmd, 
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 14, 
                  height: 1.4, 
                  color: Colors.red, 
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    if (line.isPrompt) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 2.0), 
        child: RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: "${connection.username}@${connection.host}:~\$ ", 
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 14, 
                  height: 1.4, 
                  color: Colors.greenAccent, 
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextSpan(
                text: line.text, 
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 14, 
                  height: 1.4, 
                  color: Colors.red,
                ),
              ),
              if (isLastPrompt && focusNode.hasFocus)
                WidgetSpan(
                  child: Container(
                    width: 8, 
                    height: 18, 
                    color: Colors.white.withValues(alpha: 0.8), 
                    margin: const EdgeInsets.only(left: 1),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    
    Color textColor = line.isWelcome 
        ? systemColor 
        : (line.isSystem ? Colors.redAccent : Colors.white);
        
    return Padding(
      padding: const EdgeInsets.only(bottom: 2.0), 
      child: SelectableText(
        line.text, 
        style: GoogleFonts.jetBrainsMono(
          fontSize: 14, 
          height: 1.4, 
          color: textColor, 
          fontWeight: line.isWelcome ? FontWeight.w600 : FontWeight.normal, 
          shadows: line.isWelcome 
              ? [Shadow(color: textColor.withValues(alpha: 0.5), blurRadius: 4)] 
              : null,
        ),
      ),
    );
  }
}