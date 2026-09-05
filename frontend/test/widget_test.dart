import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/main.dart';

void main() {
  testWidgets('NexusApp smoke test — arranca sin errores', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: NexusApp()));
    // Solo verifica que el árbol de widgets se construya sin lanzar excepciones.
    expect(tester.takeException(), isNull);
  });
}
