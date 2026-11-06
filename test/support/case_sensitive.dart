// Folders that tell file names apart by case, for the tests that need one.

import 'dart:io';

/// Makes [dir] case-sensitive on Windows (`fsutil file
/// setCaseSensitiveInfo`), and returns whether it now is. `fsutil` exits 0
/// even where it can't set the flag (it prints "Access is denied." and
/// leaves the folder as it was), so the folder is asked, not `fsutil`:
/// [isCaseSensitive]. False off Windows, and where `fsutil` can't run.
bool makeCaseSensitive(Directory dir) {
  if (!Platform.isWindows) return false;
  try {
    final made = Process.runSync('fsutil.exe', [
      'file',
      'setCaseSensitiveInfo',
      dir.path,
      'enable',
    ]);
    if (made.exitCode != 0) return false;
  } on ProcessException {
    return false;
  }
  return isCaseSensitive(dir);
}

/// Whether [dir] tells file names apart by case: a file made as
/// `case_probe` is not found as `CASE_PROBE`.
bool isCaseSensitive(Directory dir) {
  final probe = File('${dir.path}/case_probe')..writeAsStringSync('');
  try {
    return !File('${dir.path}/CASE_PROBE').existsSync();
  } finally {
    probe.deleteSync();
  }
}
