import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../management/presentation/management_provider.dart';
import '../../saas_admin/presentation/saas_provider.dart';

/// "Mis datos" — quién soy dentro de este negocio.
///
/// Sólo el nombre se edita: el correo es con el que se entra a la app y el
/// rol lo asigna quien administra usuarios, no uno mismo.
class PersonalDataScreen extends ConsumerStatefulWidget {
  const PersonalDataScreen({super.key});

  @override
  ConsumerState<PersonalDataScreen> createState() => _PersonalDataScreenState();
}

class _PersonalDataScreenState extends ConsumerState<PersonalDataScreen> {
  final _nameController = TextEditingController();
  bool _initialized = false;
  bool _isSaving = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save(String memberId) async {
    final name = _nameController.text.trim();
    if (name.length < 3 || _isSaving) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await ref.read(membersProvider.notifier).edit(id: memberId, name: name);
      messenger.showSnackBar(
        const SnackBar(content: Text('Listo, tus datos quedaron guardados.')),
      );
      if (mounted) setState(() => _isSaving = false);
    } catch (e) {
      setState(() {
        _isSaving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final member = ref.watch(currentMemberProvider).valueOrNull;
    final role = ref.watch(myRoleProvider);
    final tenant = ref.watch(saasProfileProvider).valueOrNull?.tenantName;

    if (member != null && !_initialized) {
      _nameController.text = member.name;
      _initialized = true;
    }

    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      appBar: AppBar(
        backgroundColor: AppColors.darkSlate,
        title: const Text('Mis datos'),
      ),
      body: member == null
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.emerald))
          : ListView(
              padding: EdgeInsets.fromLTRB(
                  16, 16, 16, 32 + MediaQuery.of(context).padding.bottom),
              children: [
                const _Label('Nombre'),
                const SizedBox(height: 6),
                TextField(
                  key: const Key('personalNameField'),
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setState(() {}),
                  style:
                      const TextStyle(color: AppColors.onSurface, fontSize: 15),
                  decoration: const InputDecoration(
                    hintText: 'Como quieres que te vean en los tickets',
                    prefixIcon: Icon(Icons.person_outline_rounded, size: 18),
                  ),
                ),
                const SizedBox(height: 22),
                _ReadOnlyField(
                  label: 'Correo',
                  value: member.email,
                  hint: 'Es con el que entras a la app',
                  icon: Icons.alternate_email_rounded,
                ),
                const SizedBox(height: 22),
                _ReadOnlyField(
                  label: 'Rol',
                  value: role?.label ?? member.roleId,
                  hint: 'Lo asigna quien administra los usuarios',
                  icon: Icons.shield_outlined,
                ),
                const SizedBox(height: 22),
                _ReadOnlyField(
                  label: 'Negocio',
                  value: tenant?.isNotEmpty == true ? tenant! : 'Mi negocio',
                  hint: 'La tienda a la que perteneces',
                  icon: Icons.storefront_rounded,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 18),
                  Text(_error!,
                      key: const Key('personalDataError'),
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.error)),
                ],
                const SizedBox(height: 30),
                ElevatedButton(
                  key: const Key('personalSaveButton'),
                  onPressed: _nameController.text.trim().length >= 3 &&
                          _nameController.text.trim() != member.name &&
                          !_isSaving
                      ? () => _save(member.id)
                      : null,
                  child: _isSaving
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: AppColors.darkSlate),
                        )
                      : const Text('Guardar cambios'),
                ),
              ],
            ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppColors.onSurface,
        ),
      );
}

/// Dato que se muestra pero no se edita — con el porqué a la vista, para que
/// no parezca un campo roto.
class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({
    required this.label,
    required this.value,
    required this.hint,
    required this.icon,
  });

  final String label;
  final String value;
  final String hint;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Label(label),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppColors.onSurfaceMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(
                      fontSize: 15, color: AppColors.onSurfaceMuted),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 5),
        Text(
          hint,
          style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceMuted),
        ),
      ],
    );
  }
}
