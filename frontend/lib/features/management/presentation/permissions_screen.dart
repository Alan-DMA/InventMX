import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../domain/app_permission.dart';
import '../domain/tenant_role.dart';
import 'management_provider.dart';
import 'widgets/role_customize_dialog.dart';

/// Gestión → Permisos: qué puede hacer cada rol del comercio.
///
/// Se organiza por **rol**, no por persona: es como está modelado el backend
/// (`role_permissions`) y evita que dos cajeros terminen con accesos distintos
/// sin que nadie sepa por qué.
///
/// Desde la Fase B (Sep 2026) el **dueño** puede ajustar los roles a su tienda:
/// la primera edición de un rol de fábrica crea su propia versión y los
/// empleados que lo tenían pasan a ella (clone-on-write, con confirmación).
/// El Encargado entra pero sólo lee — si pudiera editar, se ampliaría sus
/// propios accesos. El rol Dueño no se toca y ningún rol pierde
/// `inventory.view`.
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
    final canEdit = ref.watch(canEditPermissionsProvider);
    // Se observa la plantilla aunque no se pinte: el aviso de "esto afecta a N
    // personas" la necesita cargada en el momento del toque, no después.
    ref.watch(membersProvider);
    // Editable de verdad: el dueño, y sobre un rol que no sea el suyo.
    final editable = canEdit && selected.isEditable;

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
          child: Row(
            children: [
              Expanded(
                child: Text(
                  selected.description,
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.onSurfaceMuted),
                ),
              ),
              // Distintivo del rol ajustado a esta tienda
              if (selected.isCustom)
                Container(
                  key: const Key('roleCustomChip'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.emerald.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Ajustado a tu tienda',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.emerald,
                    ),
                  ),
                ),
            ],
          ),
        ),
        _Hint(role: selected, canEdit: canEdit),
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
                            editable: editable,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              if (selected.isCustom && canEdit) ...[
                const SizedBox(height: 20),
                TextButton.icon(
                  key: const Key('roleResetButton'),
                  onPressed: () => _reset(context, ref, selected),
                  icon: const Icon(Icons.restart_alt_rounded,
                      size: 18, color: AppColors.warning),
                  label: const Text(
                    'Restablecer al estándar',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.warning,
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

  Future<void> _reset(
      BuildContext context, WidgetRef ref, TenantRole role) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await confirmRoleReset(
      context,
      role: role,
      affectedMembers: ref.read(membersWithRoleProvider(role.id)),
    );
    if (!confirmed) return;
    try {
      await ref.read(rolesProvider.notifier).reset(role.id);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }
}

/// Explica en una línea por qué esta pantalla se comporta como se comporta.
class _Hint extends StatelessWidget {
  const _Hint({required this.role, required this.canEdit});

  final TenantRole role;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final (icon, text) = switch ((canEdit, role.isEditable)) {
      (false, _) => (
          Icons.lock_outline_rounded,
          'Sólo el dueño puede cambiar los permisos de un rol',
        ),
      (true, false) => (
          Icons.verified_user_outlined,
          'El dueño tiene acceso a todo por definición: este rol no se ajusta',
        ),
      (true, true) => (
          Icons.tune_rounded,
          'Ajusta lo que puede hacer este rol en tu tienda',
        ),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.onSurfaceMuted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              key: const Key('permissionsHint'),
              style: const TextStyle(
                  fontSize: 11.5, color: AppColors.onSurfaceMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionRow extends ConsumerWidget {
  const _PermissionRow({
    required this.role,
    required this.permission,
    required this.editable,
  });

  final TenantRole role;
  final AppPermission permission;
  final bool editable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final granted = role.can(permission.name);
    // Sin "ver inventario" la app queda en blanco y el empleado no entiende
    // qué le pasó: se muestra bloqueado en vez de dejar intentarlo para
    // después rechazarlo desde el servidor.
    final locked = permission.name == Permissions.inventoryView;

    if (!editable) {
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
              'Sin esto la app se ve vacía',
              style: TextStyle(fontSize: 11, color: AppColors.onSurfaceMuted),
            )
          : null,
    );
  }

  Future<void> _toggle(
      BuildContext context, WidgetRef ref, bool granted) async {
    final messenger = ScaffoldMessenger.of(context);

    // La primera vez que se ajusta un rol de fábrica se avisa a quién afecta.
    if (!role.isCustom) {
      final confirmed = await confirmRoleCustomization(
        context,
        role: role,
        affectedMembers: ref.read(membersWithRoleProvider(role.id)),
      );
      if (!confirmed) return;
    }

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
