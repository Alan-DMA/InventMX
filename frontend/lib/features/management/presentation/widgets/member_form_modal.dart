import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/tenant_member.dart';
import '../../domain/tenant_role.dart';
import '../management_provider.dart';

/// Alta y edición de una persona del comercio. Con [initial] abre en edición.
Future<void> showMemberFormModal(
  BuildContext context, {
  TenantMember? initial,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) => MemberFormModal(initial: initial),
  );
}

class MemberFormModal extends ConsumerStatefulWidget {
  const MemberFormModal({super.key, this.initial});

  final TenantMember? initial;

  bool get isEditing => initial != null;

  @override
  ConsumerState<MemberFormModal> createState() => _MemberFormModalState();
}

class _MemberFormModalState extends ConsumerState<MemberFormModal> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _nameFocus = FocusNode();
  final _emailFocus = FocusNode();

  late String _roleId;
  bool _isSaving = false;
  bool _isValid = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _nameController.text = initial?.name ?? '';
    _emailController.text = initial?.email ?? '';
    _roleId = initial?.roleId ?? TenantRoles.cashier;

    _nameController.addListener(_validate);
    _emailController.addListener(_validate);
    _validate();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _nameFocus.requestFocus());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _nameFocus.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  void _validate() {
    final email = _emailController.text.trim();
    final valid = _nameController.text.trim().length >= 3 &&
        RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
    if (valid != _isValid) setState(() => _isValid = valid);
  }

  Future<void> _submit() async {
    if (!_isValid || _isSaving) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final notifier = ref.read(membersProvider.notifier);
    try {
      if (widget.isEditing) {
        await notifier.edit(
          id: widget.initial!.id,
          name: name,
          email: email,
          roleId: _roleId,
        );
      } else {
        await notifier.create(name: name, email: email, roleId: _roleId);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _isSaving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottomInset = max(mq.viewInsets.bottom, mq.padding.bottom);
    final roles = ref.watch(rolesProvider).valueOrNull ?? const <TenantRole>[];

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + bottomInset),
      // Los RadioListTile de rol pintan su tinta sobre el Material más
      // cercano: sin éste, el fondo de la hoja taparía el splash.
      child: Material(
        type: MaterialType.transparency,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.isEditing ? 'Editar usuario' : 'Nuevo usuario',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded,
                        size: 22, color: AppColors.onSurfaceMuted),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Cerrar',
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _label('Nombre'),
              const SizedBox(height: 6),
              TextFormField(
                key: const Key('memberNameField'),
                controller: _nameController,
                focusNode: _nameFocus,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                style:
                    const TextStyle(color: AppColors.onSurface, fontSize: 15),
                decoration: const InputDecoration(
                  hintText: 'Ej: Ana Torres',
                  prefixIcon: Icon(Icons.person_outline_rounded, size: 18),
                ),
                onFieldSubmitted: (_) => _emailFocus.requestFocus(),
              ),
              const SizedBox(height: 16),
              _label('Correo'),
              const SizedBox(height: 6),
              TextFormField(
                key: const Key('memberEmailField'),
                controller: _emailController,
                focusNode: _emailFocus,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                style:
                    const TextStyle(color: AppColors.onSurface, fontSize: 15),
                decoration: const InputDecoration(
                  hintText: 'Ej: ana@minegocio.mx',
                  prefixIcon: Icon(Icons.alternate_email_rounded, size: 18),
                ),
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 4),
              const Text(
                'Con este correo entra a la app.',
                style: TextStyle(fontSize: 11, color: AppColors.onSurfaceMuted),
              ),
              const SizedBox(height: 16),
              _label('Rol'),
              const SizedBox(height: 6),
              // El rol define los permisos: se elige de aquí, y lo que cada
              // rol puede hacer se edita en Gestión → Permisos. Sin descripción
              // por renglón a propósito: con cuatro roles descritos, el botón
              // de guardar caía fuera de pantalla en un teléfono.
              for (final role in roles)
                RadioListTile<String>(
                  key: Key('memberRole-${role.id}'),
                  value: role.id,
                  // ignore: deprecated_member_use
                  groupValue: _roleId,
                  // ignore: deprecated_member_use
                  onChanged: (value) => setState(() => _roleId = value!),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: AppColors.emerald,
                  visualDensity: VisualDensity.compact,
                  title: Text(
                    role.label,
                    style: const TextStyle(
                        color: AppColors.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          size: 16, color: AppColors.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          key: const Key('memberFormError'),
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.error),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                key: const Key('memberSaveButton'),
                onPressed: _isValid && !_isSaving ? _submit : null,
                child: _isSaving
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: AppColors.darkSlate),
                      )
                    : Text(
                        widget.isEditing ? 'Guardar cambios' : 'Crear usuario'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppColors.onSurface,
        ),
      );
}
