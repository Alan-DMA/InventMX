import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../domain/app_permission.dart';
import '../domain/tenant_role.dart';
import 'management_provider.dart';

/// Gestión → Permisos: qué puede hacer cada rol del comercio.
///
/// Se edita por **rol**, no por persona: es como está modelado en el backend
/// (`role_permissions`), y evita que dos cajeros terminen con accesos
/// distintos sin que nadie sepa por qué.
class PermissionsScreen extends ConsumerStatefulWidget {
  const PermissionsScreen({super.key});

  @override
  ConsumerState<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends ConsumerState<PermissionsScreen> {
  String? _selectedRoleId;

  @override
  Widget build(BuildContext context) {
    final roles = ref.watch(rolesProvider);

    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      appBar: AppBar(
        backgroundColor: AppColors.darkSlate,
        title: const Text('Permisos'),
      ),
      body: roles.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.emerald)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              e.toString().replaceFirst('Exception: ', ''),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.onSurfaceMuted),
            ),
          ),
        ),
        data: (items) {
          if (items.isEmpty) return const SizedBox.shrink();
          final selected = items.firstWhere(
            (r) => r.id == _selectedRoleId,
            orElse: () => items.first,
          );
          return _Matrix(
            roles: items,
            selected: selected,
            onSelect: (role) => setState(() => _selectedRoleId = role.id),
          );
        },
      ),
    );
  }
}

class _Matrix extends ConsumerWidget {
  const _Matrix({
    required this.roles,
    required this.selected,
    required this.onSelect,
  });

  final List<TenantRole> roles;
  final TenantRole selected;
  final ValueChanged<TenantRole> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modules = Permissions.moduleLabels.keys.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final role in roles)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    key: Key('roleChip-${role.id}'),
                    label: Text(role.label),
                    selected: role.id == selected.id,
                    onSelected: (_) => onSelect(role),
                    backgroundColor: AppColors.surface,
                    selectedColor: AppColors.emerald.withValues(alpha: 0.2),
                    side: BorderSide(
                      color: role.id == selected.id
                          ? AppColors.emerald
                          : AppColors.border,
                    ),
                    labelStyle: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: role.id == selected.id
                          ? AppColors.emerald
                          : AppColors.onSurfaceMuted,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            selected.description,
            style: const TextStyle(
                fontSize: 12.5, color: AppColors.onSurfaceMuted),
          ),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
                16, 12, 16, 32 + MediaQuery.of(context).padding.bottom),
            children: [
              for (final module in modules) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
                  child: Text(
                    Permissions.moduleLabels[module]!.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: AppColors.onSurfaceMuted,
                    ),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  // El SwitchListTile pinta su tinta sobre el Material más
                  // cercano; sin éste el fondo de la tarjeta la taparía.
                  child: Material(
                    type: MaterialType.transparency,
                    child: Column(
                      children: [
                        for (final permission in Permissions.ofModule(module))
                          _PermissionRow(
                            role: selected,
                            permission: permission,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PermissionRow extends ConsumerWidget {
  const _PermissionRow({required this.role, required this.permission});

  final TenantRole role;
  final AppPermission permission;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final granted = role.can(permission.name);
    // El permiso que sostiene la administración del negocio no se puede
    // apagar en el rol que lo garantiza: se muestra bloqueado en vez de
    // dejar intentarlo para después rechazarlo.
    final locked = TenantRoles.undroppable[role.id] == permission.name;

    return SwitchListTile(
      key: Key('perm-${role.id}-${permission.name}'),
      value: granted,
      onChanged: locked ? null : (value) => _toggle(context, ref, value),
      dense: true,
      activeThumbColor: AppColors.emerald,
      contentPadding: const EdgeInsets.fromLTRB(14, 0, 8, 0),
      title: Text(
        permission.description,
        style: TextStyle(
          fontSize: 13.5,
          color: locked ? AppColors.onSurfaceMuted : AppColors.onSurface,
        ),
      ),
      subtitle: locked
          ? const Text(
              'Sin esto nadie podría repartir accesos',
              style: TextStyle(fontSize: 11, color: AppColors.onSurfaceMuted),
            )
          : null,
    );
  }

  Future<void> _toggle(
      BuildContext context, WidgetRef ref, bool granted) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(rolesProvider.notifier).toggle(
            role: role,
            permission: permission.name,
            granted: granted,
          );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }
}
