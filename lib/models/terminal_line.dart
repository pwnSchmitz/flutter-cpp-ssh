class TerminalLine {
  String text;
  bool isPrompt, isSystem, isWelcome, isOutput;
  
  TerminalLine({
    this.text = '',
    this.isSystem = false,
    this.isWelcome = false,
    this.isOutput = false,
    this.isPrompt = false,
  });
}