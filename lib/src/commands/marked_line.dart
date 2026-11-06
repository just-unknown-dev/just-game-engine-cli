/// The lines `just game check` and `just game scene validate` print: a
/// mark, then what was found.
library;

import 'package:just_core_cli/just_core_cli.dart';
import 'package:meta/meta.dart';

/// [text] after a mark for [severity]: `ok  `, ` !  ` or `x   ` in plain
/// text, as these commands always printed (scripts read them), and a
/// coloured ✓, ! or ✗ at a terminal ([Output.style]).
@internal
String marked(Output output, Severity severity, String text) {
  final style = output.style;
  if (style.colors) return '${style.mark(severity)}  $text';
  return switch (severity) {
        Severity.ok => 'ok  ',
        Severity.warning => ' !  ',
        Severity.problem => 'x   ',
      } +
      text;
}
