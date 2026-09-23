import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../domain/app_permission.dart';
import '../domain/tenant_role.dart';
import 'management_provider.dart';

/// Gestión → Permisos: qué puede hacer cada rol del comercio.
///
/// **Sólo lectura** (Permisos por rol, Fase A): muestra los permisos reales
/// que manda el servidor por rol. Se organiza por **rol**, no por persona,
/// porque así está modelado el backend (`role_permissions`) y evita que dos
/// cajeros terminen con accesos distintos sin que nadie sepa por qué.
/// Personalizarlos por comercio (clone-on-write de los roles globales) es la
/// Fase B — hasta entonces no se ofrecen switches que luego no guardarían.
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
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Row(
            children: [
              Icon(Icons.lock_outline_rounded,
                  size: 14, color: AppColors.onSurfaceMuted),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Los roles son estándar en esta versión',
                  key: Key('permissionsReadOnly'),
                  style: TextStyle(
                      fontSize: 11.5, color: AppColors.onSurfaceMuted),
                ),
              ),
            ],
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
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({required this.role, required this.permission});

  final TenantRole role;
  final AppPermission permission;

  @override
  Widget build(BuildContext context) {
    final granted = role.can(permission.name);

    return ListTile(
      key: Key('perm-${role.id}-${permission.name}'),
      dense: true,
      contentPadding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
      leading: Icon(
        granted ? Icons.check_circle_rounded : Icons.remove_circle_outline,
        size: 20,
        color: granted ? AppColors.emerald : AppColors.onSurfaceMuted,
      ),
      title: Text(
        permission.description,
        style: TextStyle(
          fontSize: 13.5,
          color: granted ? AppColors.onSurface : AppColors.onSurfaceMuted,
        ),
      ),
    );
  }
}
