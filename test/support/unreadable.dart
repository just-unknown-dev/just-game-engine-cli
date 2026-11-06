// Folders nobody may list, for the tests of what happens when one is in
// the way.

import 'dart:io';

/// Makes [dir] unlistable — on Windows by denying Everyone its read and
/// list rights (`icacls`), elsewhere with `chmod 000` — and returns whether
/// listing it now fails: false where the rights can't be taken away (say,
/// running as root). Undo it with [makeReadable] before deleting [dir].
bool makeUnreadable(Directory dir) {
  try {
    final made = Platform.isWindows
        ? Process.runSync('icacls', [
            dir.path,
            '/deny',
            '*S-1-1-0:(OI)(CI)(RX)',
          ])
        : Process.runSync('chmod', ['000', dir.path]);
    if (made.exitCode != 0) return false;
  } on ProcessException {
    return false;
  }
  try {
    dir.listSync();
    return false;
  } on FileSystemException {
    return true;
  }
}

/// Gives [dir] back the rights [makeUnreadable] took.
void makeReadable(Directory dir) {
  try {
    Platform.isWindows
        ? Process.runSync('icacls', [dir.path, '/remove:d', '*S-1-1-0'])
        : Process.runSync('chmod', ['755', dir.path]);
  } on ProcessException {
    // Nothing to give back.
  }
}
