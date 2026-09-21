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
  final _passwordController = TextEditingController();
  final _rateController = TextEditingController();
  final _nameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  /// Vacío hasta que se conocen los roles: entonces se elige "Cajero" (o el
  /// primero) — con el backend real los ids son UUID, no se pueden fijar aquí.
  String _roleId = '';

  /// Esquema de comisión. `null` = "No comisiona" (valor por defecto, sin
  /// sugerir ninguno: la tasa la decide el dueño).
  CommissionType? _commissionType;
  bool _isSaving = false;
  bool _isValid = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _nameController.text = initial?.name ?? '';
    _emailController.text = initial?.email ?? '';
    _roleId = initial?.roleId ?? '';
    if (initial != null && initial.hasCommission) {
      _commissionType = initial.commissionType;
      final r = initial.commissionRate;
      _rateController.text = r == r.roundToDouble()
          ? r.toStringAsFixed(0)
          : r.toStringAsFixed(2);
    }

    _nameController.addListener(_validate);
    _emailController.addListener(_validate);
    _passwordController.addListener(_validate);
    _rateController.addListener(_onRateChanged);
    _validate();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _nameFocus.requestFocus());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _rateController.dispose();
    _nameFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  /// Tasa tecleada, o null si está vacía o no es número.
  double? get _rate => double.tryParse(_rateController.text.trim().replaceAll(',', '.'));

  /// Con esquema elegido, la tasa tiene que ser un número > 0 (y ≤ 100 si es
  /// porcentaje) — el backend rechaza lo demás con 400.
  bool get _commissionValid {
    if (_commissionType == null) return true;
    final r = _rate;
    if (r == null || r <= 0) return false;
    return _commissionType == CommissionType.fixedPerSale || r <= 100;
  }

  void _onRateChanged() => setState(_validate);

  void _validate() {
    final email = _emailController.text.trim();
    final passwordOk =
        widget.isEditing || _passwordController.text.trim().length >= 6;
    final valid = _nameController.text.trim().length >= 3 &&
        RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email) &&
        passwordOk &&
        _roleId.isNotEmpty &&
        _commissionValid;
    if (valid != _isValid) setState(() => _isValid = valid);
  }

  /// "Con 5 %, una venta de \$200 le deja \$10." — el ejemplo hace tangible
  /// la tasa sin pedirle cuentas al dueño.
  String? get _commissionExample {
    final r = _rate;
    if (_commissionType == null || r == null || r <= 0) return null;
    String money(double v) => '\$${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2)}';
    final pct = r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toStringAsFixed(2);
    return switch (_commissionType!) {
      CommissionType.percentageSale =>
        'Con $pct %, una venta de \$200 le deja ${money(200 * r / 100)}.',
      CommissionType.percentageProfit =>
        'Con $pct %, una venta de \$200 con \$60 de ganancia le deja ${money(60 * r / 100)}.',
      CommissionType.fixedPerSale =>
        'Cada venta que cobre le deja ${money(r)}, sin importar el monto.',
    };
  }

  Future<void> _submit() async {
    if (!_isValid || _isSaving) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final commissionType = _commissionType ?? CommissionType.percentageSale;
    final commissionRate = _commissionType == null ? 0.0 : (_rate ?? 0);
    final notifier = ref.read(membersProvider.notifier);
    try {
      if (widget.isEditing) {
        await notifier.edit(
          id: widget.initial!.id,
          name: name,
          roleId: _roleId,
          commissionType: commissionType,
          commissionRate: commissionRate,
        );
      } else {
        await notifier.create(
          name: name,
          email: email,
          roleId: _roleId,
          password: _passwordController.text.trim(),
          commissionType: commissionType,
          commissionRate: commissionRate,
        );
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
    if (_roleId.isEmpty && roles.isNotEmpty) {
      // Cajero por defecto: es el rol que más se da de alta en una tiendita.
      _roleId = roles
          .firstWhere((r) => r.code == RoleCodes.cashier, orElse: () => roles.first)
          .id;
      WidgetsBinding.instance.addPostFrameCallback((_) => _validate());
    }

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
                // El backend no permite cambiar el correo de una cuenta.
                readOnly: widget.isEditing,
                enabled: !widget.isEditing,
                keyboardType: TextInputType.emailAddress,
                textInputAction:
                    widget.isEditing ? TextInputAction.done : TextInputAction.next,
                style:
                    const TextStyle(color: AppColors.onSurface, fontSize: 15),
                decoration: const InputDecoration(
                  hintText: 'Ej: ana@minegocio.mx',
                  prefixIcon: Icon(Icons.alternate_email_rounded, size: 18),
                ),
                onFieldSubmitted: (_) => widget.isEditing
                    ? _submit()
                    : _passwordFocus.requestFocus(),
              ),
              const SizedBox(height: 4),
              Text(
                widget.isEditing
                    ? 'El correo no se puede cambiar.'
                    : 'Con este correo entra a la app.',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.onSurfaceMuted),
              ),
              if (!widget.isEditing) ...[
                const SizedBox(height: 16),
                _label('Contraseña inicial'),
                const SizedBox(height: 6),
                TextFormField(
                  key: const Key('memberPasswordField'),
                  controller: _passwordController,
                  focusNode: _passwordFocus,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  style: const TextStyle(
                      color: AppColors.onSurface, fontSize: 15),
                  decoration: const InputDecoration(
                    hintText: 'Mínimo 6 caracteres',
                    prefixIcon: Icon(Icons.lock_outline_rounded, size: 18),
                  ),
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Tú se la dices; podrá cambiarla desde su cuenta.',
                  style:
                      TextStyle(fontSize: 11, color: AppColors.onSurfaceMuted),
                ),
              ],
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
              const SizedBox(height: 16),
              _label('Comisión'),
              const SizedBox(height: 6),
              // Sin opción pre-marcada más allá de "No comisiona" y sin tasa
              // sugerida: la decide el dueño (RF-10). El ejemplo de abajo
              // traduce el porcentaje a pesos para que no haya que calcular.
              for (final option in _commissionOptions)
                RadioListTile<CommissionType?>(
                  key: Key('memberCommission-${option.$1?.apiValue ?? 'none'}'),
                  value: option.$1,
                  // ignore: deprecated_member_use
                  groupValue: _commissionType,
                  // ignore: deprecated_member_use
                  onChanged: (value) => setState(() {
                    _commissionType = value;
                    _validate();
                  }),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: AppColors.emerald,
                  visualDensity: VisualDensity.compact,
                  title: Text(
                    option.$2,
                    style: const TextStyle(
                        color: AppColors.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              if (_commissionType != null) ...[
                const SizedBox(height: 6),
                TextFormField(
                  key: const Key('memberCommissionRateField'),
                  controller: _rateController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.done,
                  style: const TextStyle(
                      color: AppColors.onSurface, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: _commissionType == CommissionType.fixedPerSale
                        ? 'Ej: 15'
                        : 'Ej: 5',
                    prefixIcon: Icon(
                      _commissionType == CommissionType.fixedPerSale
                          ? Icons.attach_money_rounded
                          : Icons.percent_rounded,
                      size: 18,
                    ),
                    suffixText: _commissionType == CommissionType.fixedPerSale
                        ? 'MXN por venta'
                        : '%',
                  ),
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 4),
                Text(
                  _commissionExample ??
                      (_commissionType == CommissionType.fixedPerSale
                          ? 'Monto en pesos por cada venta cobrada.'
                          : 'Porcentaje entre 0 y 100.'),
                  key: const Key('memberCommissionExample'),
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.onSurfaceMuted),
                ),
              ],
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

  /// (tipo, etiqueta) — `null` es "No comisiona". Lenguaje de tendero.
  static const _commissionOptions = <(CommissionType?, String)>[
    (null, 'No comisiona'),
    (CommissionType.percentageSale, '% de lo que vende'),
    (CommissionType.percentageProfit, '% de la ganancia'),
    (CommissionType.fixedPerSale, '\$ fijos por venta'),
  ];

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppColors.onSurface,
        ),
      );
}
