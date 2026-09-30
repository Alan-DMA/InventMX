import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/admin_theme.dart';
import 'router/admin_router.dart';

/// App web del panel de plataforma (Centro de soporte, etapa 3). Vive aparte
/// de la app del tendero (P1): ésta nunca importa `lib/admin/`.
class AdminApp extends ConsumerWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
        title: 'Nexus · Panel de plataforma',
        debugShowCheckedModeBanner: false,
        theme: buildAdminTheme(),
        routerConfig: ref.watch(adminRouterProvider),
      );
}
