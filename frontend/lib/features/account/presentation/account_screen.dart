import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/settings_group.dart';
import '../../auth/presentation/login_provider.dart';
import '../../management/domain/tenant_member.dart';
import '../../management/domain/tenant_role.dart';
import '../../management/presentation/management_provider.dart';
import 'account_provider.dart';

/// "Mi perfil" — sólo lo propio de quien está en sesión, igual para todos
/// los roles: mis datos, mi contraseña, dónde opero, mis comisiones (si las
/// tiene) y cerrar sesión.
///
/// Lo administrativo (Usuarios, Preferencias, Suscripción, Clonar catálogo,
/// Panel de fundadores) vive en el menú ☰ con puertas por rol (Permisos por
/// rol, Fase A — decisión de Eduardo del Sep 21): aquí no hay nada que un
/// cajero no deba ver, así que la página no cambia según quién la abra.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final member = ref.watch(currentMemberProvider).valueOrNull;
    final role = ref.watch(myRoleProvider);
    final warehouse = ref.watch(operatingWarehouseProvider).valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      appBar: AppBar(
        backgroundColor: AppColors.darkSlate,
        title: const Text('Mi perfil'),
      ),
      body: member == null
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.emerald))
          : ListView(
              padding: EdgeInsets.fromLTRB(
                  16, 8, 16, 32 + MediaQuery.of(context).padding.bottom),
              children: [
                _Header(member: member, role: role),
                const SizedBox(height: 26),
                SettingsGroup(
                  label: 'Mi información',
                  rows: [
                    SettingsRow(
                      rowKey: const Key('accountRowData'),
                      icon: Icons.badge_outlined,
                      title: 'Mis datos',
                      subtitle: member.email,
                      onTap: () => context.push(AppRoutes.accountData),
                    ),
                    SettingsRow(
                      rowKey: const Key('accountRowPassword'),
                      icon: Icons.lock_outline_rounded,
                      title: 'Contraseña',
                      subtitle: 'Cámbiala cuando quieras',
                      onTap: () => context.push(AppRoutes.accountPassword),
                    ),
                    SettingsRow(
                      rowKey: const Key('accountRowWarehouse'),
                      icon: Icons.warehouse_outlined,
                      title: 'Dónde opero',
                      subtitle: warehouse?.name ?? 'Sin almacén asignado',
                      onTap: () => context.push(AppRoutes.accountWarehouse),
                    ),
                    // Sólo si le pagan comisión: sin esquema no hay nada que
                    // consultar y una pantalla en ceros confunde.
                    if (member.hasCommission)
                      SettingsRow(
                        rowKey: const Key('accountRowCommissions'),
                        icon: Icons.payments_outlined,
                        title: 'Mis comisiones',
                        subtitle: member.commissionLabel!,
                        onTap: () => context.push(AppRoutes.accountCommissions),
                      ),
                  ],
                ),
                _LogoutButton(),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.member, required this.role});

  final TenantMember member;
  final TenantRole? role;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 60,
          height: 60,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.emerald.withValues(alpha: 0.18),
            shape: BoxShape.circle,
          ),
          child: Text(
            member.initials,
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              color: AppColors.emerald,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                member.name,
                key: const Key('accountMemberName'),
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  if (role != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.skyBlue.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        role!.label,
                        key: const Key('accountRoleChip'),
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.skyBlue,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LogoutButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          key: const Key('accountLogout'),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          leading: const Icon(Icons.logout_rounded,
              size: 21, color: AppColors.error),
          title: const Text(
            'Cerrar sesión',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.error,
            ),
          ),
          onTap: () => ref.read(loginProvider.notifier).logout(),
        ),
      ),
    );
  }
}
