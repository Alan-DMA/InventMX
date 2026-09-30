import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// CA-S3.7 (P1): la app del tendero nunca importa el panel de plataforma. El
/// panel vive en `lib/admin/` y entra sólo por `lib/main_admin.dart`; si la
/// app del tendero lo importara, el código del panel viajaría en el APK.
void main() {
  test('ningún archivo fuera de lib/admin importa lib/admin', () {
    final lib = Directory('lib').absolute;
    final adminDir = Directory('lib/admin').absolute.uri.path;
    final importPattern = RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''', multiLine: true);
    final offenders = <String>[];

    for (final entity in lib.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final fileUri = entity.absolute.uri;
      if (fileUri.path.startsWith(adminDir) || fileUri.path.endsWith('/main_admin.dart')) continue;

      for (final match in importPattern.allMatches(entity.readAsStringSync())) {
        final target = match.group(1)!;
        final resolved = target.startsWith('package:nexus_app/')
            ? Directory('lib/${target.substring('package:nexus_app/'.length)}').absolute.uri.path
            : target.startsWith('package:') || target.startsWith('dart:')
                ? null
                : fileUri.resolve(target).path;
        if (resolved != null && resolved.startsWith(adminDir)) offenders.add('${entity.path} → $target');
      }
    }

    expect(offenders, isEmpty, reason: 'La app del tendero no debe importar el panel');
  });
}
