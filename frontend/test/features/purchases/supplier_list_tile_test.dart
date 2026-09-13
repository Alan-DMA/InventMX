import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/purchases/domain/supplier.dart';
import 'package:nexus_app/features/purchases/presentation/widgets/phone_launcher.dart';
import 'package:nexus_app/features/purchases/presentation/widgets/supplier_list_tile.dart';
import 'package:url_launcher/url_launcher.dart';

final _supplier = Supplier(
  id: 'sup-001',
  name: 'Distribuidora Bimbo Norte',
  phone: '+525512345678',
  balanceDueMxn: 0,
  createdAt: DateTime(2026, 1, 1),
);

Widget _buildApp(List<Uri> launchedUris) {
  return ProviderScope(
    overrides: [
      urlLauncherProvider.overrideWithValue((Uri uri, {LaunchMode mode = LaunchMode.platformDefault}) async {
        launchedUris.add(uri);
        return true;
      }),
    ],
    child: MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: SupplierListTile(supplier: _supplier, onTap: () {}),
      ),
    ),
  );
}

void main() {
  testWidgets('botón de llamada abre tel: con el teléfono del proveedor', (tester) async {
    final launched = <Uri>[];
    await tester.pumpWidget(_buildApp(launched));

    await tester.tap(find.byTooltip('Llamar'));
    await tester.pump();

    expect(launched, hasLength(1));
    expect(launched.first.toString(), 'tel:+525512345678');
  });

  testWidgets('botón de WhatsApp abre wa.me con el teléfono sin el signo +', (tester) async {
    final launched = <Uri>[];
    await tester.pumpWidget(_buildApp(launched));

    await tester.tap(find.byTooltip('WhatsApp'));
    await tester.pump();

    expect(launched, hasLength(1));
    expect(launched.first.toString(), 'https://wa.me/525512345678');
  });

  testWidgets('sin teléfono no muestra botones de acción', (tester) async {
    final supplierNoPhone = Supplier(
      id: 'sup-002',
      name: 'Proveedor sin teléfono',
      balanceDueMxn: 0,
      createdAt: DateTime(2026, 1, 1),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(body: SupplierListTile(supplier: supplierNoPhone, onTap: () {})),
        ),
      ),
    );

    expect(find.byTooltip('Llamar'), findsNothing);
    expect(find.byTooltip('WhatsApp'), findsNothing);
    expect(find.text('Sin teléfono registrado'), findsOneWidget);
  });
}
