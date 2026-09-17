import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/settings_group.dart';
import '../../auth/presentation/login_provider.dart';
import '../../inventory/presentation/widgets/clone_catalog_sheet.dart';
import '../../management/domain/tenant_member.dart';
import '../../management/domain/tenant_role.dart';
import '../../management/presentation/management_provider.dart';
import '../../saas_admin/domain/subscription.dart' show mxn;
import '../../saas_admin/presentation/saas_provider.dart';
import 'account_provider.dart';

/// "Mi cuenta" — página índice hacia todo lo que se configura.
///
/// Sustituye a la hoja modal de 14.2, que mezclaba cinco dominios sin
/// jerarquía y se desbordaba al crecer. El agrupamiento sigue la propiedad de
/// cada cosa: lo **mío** (mis datos, mi contraseña, dónde opero), lo del
/// **negocio** (gente, almacenes, suscripción) y, sólo para quien opera la
/// plataforma, el **sistema** — que ningún comerciante llega a ver.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final member = ref.watch(currentMemberProvider).valueOrNull;
    final role = ref.watch(myRoleProvider);
    final warehouse = ref.watch(operatingWarehouseProvider).valueOrNull;

    final canMembers = ref.watch(canManageMembersProvider);
    final canWarehouses = ref.watch(canManageWarehousesProvider);
    final canSubscription = ref.watch(canSeeSubscriptionProvider);
    final isCorporativo = ref.watch(isCorporativoPlanProvider);
    final isFounder = ref.watch(isFounderProvider);

    final businessRows = <Widget>[
      if (canMembers)
        SettingsRow(
          rowKey: const Key('accountRowUsers'),
          icon: Icons.groups_outlined,
          title: 'Usuarios y permisos',
          subtitle: 'Quién trabaja aquí y qué puede hacer',
          onTap: () => context.push(AppRoutes.manageMembers),
        ),
      if (canWarehouses)
        SettingsRow(
          rowKey: const Key('accountRowPreferences'),
          icon: Icons.tune_rounded,
          title: 'Preferencias operativas',
          subtitle: 'Almacenes y categorías del negocio',
          onTap: () => context.push(AppRoutes.preferences),
        ),
      if (canSubscription)
        SettingsRow(
          rowKey: const Key('accountRowSubscription'),
          icon: Icons.receipt_long_outlined,
          title: 'Mi suscripción',
          subtitle: _planLine(ref),
          onTap: () => context.push(AppRoutes.subscription),
        ),
      // RF-31, sólo Plan Corporativo (15.2.2): no se ofrece para luego negar.
      if (isCorporativo)
        SettingsRow(
          rowKey: const Key('accountRowClone'),
          icon: Icons.copy_all_rounded,
          title: 'Clonar catálogo',
          subtitle: 'Llevar tus productos a otra tienda, con stock en cero',
          onTap: () => showCloneCatalogSheet(context),
        ),
    ];

    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      appBar: AppBar(
        backgroundColor: AppColors.darkSlate,
        title: const Text('Mi cuenta'),
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
                  ],
                ),
                if (businessRows.isNotEmpty)
                  SettingsGroup(label: 'Mi negocio', rows: businessRows),
                // Operar la plataforma no es cosa de ningún comercio: sólo
                // aparece para quien administra Nexus.
                if (isFounder)
                  SettingsGroup(
                    label: 'Administración del sistema',
                    rows: [
                      SettingsRow(
                        rowKey: const Key('accountRowSystem'),
                        icon: Icons.admin_panel_settings_outlined,
                        title: 'Panel de fundadores',
                        subtitle: 'MRR, pagos por validar y comercios',
                        tint: AppColors.skyBlue,
                        onTap: () => context.push(AppRoutes.founderAdmin),
                      ),
                    ],
                  ),
                _LogoutButton(),
              ],
            ),
    );
  }

  String _planLine(WidgetRef ref) {
    final sub = ref.watch(subscriptionProvider).valueOrNull;
    final plan = sub?.plan;
    if (plan == null) return 'Tu plan y tus pagos';
    return 'Plan ${plan.name} · ${mxn(plan.priceMxn)}/mes';
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
