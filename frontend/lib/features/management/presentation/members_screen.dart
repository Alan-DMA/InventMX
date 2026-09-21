import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../domain/tenant_member.dart';
import 'management_provider.dart';
import 'widgets/management_tile.dart';
import 'widgets/member_form_modal.dart';

/// Gestión → Usuarios: quién trabaja en el comercio y con qué rol.
///
/// Sólo alcanza a la gente de este tenant (RLS) — un comerciante nunca ve
/// usuarios de otro negocio.
class MembersScreen extends ConsumerWidget {
  const MembersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(membersProvider);

    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      appBar: AppBar(
        backgroundColor: AppColors.darkSlate,
        title: const Text('Usuarios'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('memberAddFab'),
        heroTag: 'fab-member-add',
        onPressed: () => showMemberFormModal(context),
        backgroundColor: AppColors.emerald,
        foregroundColor: AppColors.darkSlate,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Nuevo usuario'),
      ),
      body: members.when(
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
        data: (items) => ListView.builder(
          padding: EdgeInsets.fromLTRB(
              16, 8, 16, 96 + MediaQuery.of(context).padding.bottom),
          itemCount: items.length,
          itemBuilder: (_, i) => _MemberTile(member: items[i]),
        ),
      ),
    );
  }
}

class _MemberTile extends ConsumerWidget {
  const _MemberTile({required this.member});

  final TenantMember member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(rolesByIdProvider)[member.roleId];
    final isMe = ref.watch(currentMemberProvider).valueOrNull?.id == member.id;

    return ManagementTile(
      itemKey: Key('member-${member.id}'),
      leading: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: member.isActive
              ? AppColors.skyBlue.withValues(alpha: 0.18)
              : AppColors.surfaceVariant,
          shape: BoxShape.circle,
        ),
        child: Text(
          member.initials,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color:
                member.isActive ? AppColors.skyBlue : AppColors.onSurfaceMuted,
          ),
        ),
      ),
      title: member.name,
      // Sin esquema no se dice "0 %": el silencio es la respuesta honesta.
      subtitle: [
        '${role?.label ?? member.roleId} · ${member.email}',
        if (member.commissionLabel != null)
          'Comisión: ${member.commissionLabel}',
      ].join('\n'),
      dimmed: !member.isActive,
      badge: !member.isActive
          ? 'Inactivo'
          : isMe
              ? 'Tú'
              : null,
      onEdit: () => showMemberFormModal(context, initial: member),
      onDeactivate:
          member.isActive ? () => _confirmDeactivate(context, ref) : null,
    );
  }

  Future<void> _confirmDeactivate(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('¿Dar de baja a esta persona?',
            style: TextStyle(color: AppColors.onSurface)),
        content: Text(
          '${member.name} dejará de poder entrar al negocio. Lo que ya '
          'registró se conserva.',
          style: const TextStyle(color: AppColors.onSurfaceMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            key: const Key('memberDeactivateConfirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Dar de baja',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(membersProvider.notifier).deactivate(member.id);
      messenger.showSnackBar(
        SnackBar(content: Text('${member.name} ya no tiene acceso.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }
}
