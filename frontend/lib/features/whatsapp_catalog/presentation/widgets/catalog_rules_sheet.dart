import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/catalog_settings.dart';

/// Valores que devuelve la hoja al guardar (U-08 / WC-01).
class CatalogRules {
  const CatalogRules({
    required this.minOrderAmountMxn,
    required this.deliveryFeeMxn,
    required this.deliveryEnabled,
    required this.pickupEnabled,
    required this.businessHours,
    required this.welcomeMessage,
  });

  final double minOrderAmountMxn;
  final double deliveryFeeMxn;
  final bool deliveryEnabled;
  final bool pickupEnabled;
  final String businessHours;
  final String welcomeMessage;
}

/// Reglas de la tienda que la vitrina pública ya respeta: pedido mínimo,
/// costo de envío, entrega a domicilio / recoger en tienda, horario y
/// mensaje de bienvenida. Devuelve `null` si se cierra sin guardar.
Future<CatalogRules?> showCatalogRulesSheet(
  BuildContext context,
  CatalogSettings current,
) {
  return showModalBottomSheet<CatalogRules>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => CatalogRulesSheet(current: current),
  );
}

class CatalogRulesSheet extends StatefulWidget {
  const CatalogRulesSheet({super.key, required this.current});

  final CatalogSettings current;

  @override
  State<CatalogRulesSheet> createState() => _CatalogRulesSheetState();
}

class _CatalogRulesSheetState extends State<CatalogRulesSheet> {
  late final TextEditingController _minOrder;
  late final TextEditingController _deliveryFee;
  late final TextEditingController _hours;
  late final TextEditingController _welcome;
  late bool _delivery;
  late bool _pickup;

  @override
  void initState() {
    super.initState();
    final c = widget.current;
    _minOrder = TextEditingController(text: _money(c.minOrderAmountMxn));
    _deliveryFee = TextEditingController(text: _money(c.deliveryFeeMxn));
    _hours = TextEditingController(text: c.businessHours ?? '');
    _welcome = TextEditingController(text: c.welcomeMessage ?? '');
    _delivery = c.deliveryEnabled;
    _pickup = c.pickupEnabled;
  }

  @override
  void dispose() {
    _minOrder.dispose();
    _deliveryFee.dispose();
    _hours.dispose();
    _welcome.dispose();
    super.dispose();
  }

  static String _money(double v) => v == 0 ? '' : v.toStringAsFixed(2);

  static double _parse(String s) =>
      double.tryParse(s.replaceAll(',', '.').trim()) ?? 0;

  /// Al menos una forma de entrega: sin ella la vitrina no podría cerrar
  /// ningún pedido y el cliente no sabría por qué.
  bool get _valid => _delivery || _pickup;

  void _save() {
    if (!_valid) return;
    Navigator.of(context).pop(CatalogRules(
      minOrderAmountMxn: _parse(_minOrder.text),
      deliveryFeeMxn: _delivery ? _parse(_deliveryFee.text) : 0,
      deliveryEnabled: _delivery,
      pickupEnabled: _pickup,
      businessHours: _hours.text.trim(),
      welcomeMessage: _welcome.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Reglas de tu tienda',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.onSurface),
              ),
              const SizedBox(height: 6),
              const Text(
                'El cliente las ve en tu catálogo antes de pedir. Deja en blanco lo que no apliques.',
                style: TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted, height: 1.4),
              ),
              const SizedBox(height: 20),

              // ── Cómo entregas ──────────────────────────────────────────
              _SwitchRow(
                key: const Key('rulesPickup'),
                title: 'Recoger en tienda',
                subtitle: 'El cliente pasa por su pedido.',
                value: _pickup,
                onChanged: (v) => setState(() => _pickup = v),
              ),
              _SwitchRow(
                key: const Key('rulesDelivery'),
                title: 'Entrega a domicilio',
                subtitle: _delivery ? 'Pide la dirección al hacer el pedido.' : 'Solo recoger en tienda.',
                value: _delivery,
                onChanged: (v) => setState(() => _delivery = v),
              ),
              if (!_valid)
                const Padding(
                  padding: EdgeInsets.only(top: 4, bottom: 8),
                  child: Text(
                    'Activa al menos una forma de entrega.',
                    key: Key('rulesDeliveryError'),
                    style: TextStyle(fontSize: 12, color: AppColors.error),
                  ),
                ),
              if (_delivery) ...[
                const SizedBox(height: 8),
                _MoneyField(
                  key: const Key('rulesDeliveryFee'),
                  controller: _deliveryFee,
                  label: 'Costo de envío',
                  helper: 'Se suma al total. En blanco = envío gratis.',
                ),
              ],
              const SizedBox(height: 12),
              _MoneyField(
                key: const Key('rulesMinOrder'),
                controller: _minOrder,
                label: 'Pedido mínimo',
                helper: 'Por debajo de esto no se puede enviar el pedido. En blanco = sin mínimo.',
              ),
              const SizedBox(height: 16),

              // ── Horario y bienvenida ───────────────────────────────────
              TextField(
                key: const Key('rulesHours'),
                controller: _hours,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(color: AppColors.onSurface),
                decoration: const InputDecoration(
                  labelText: 'Horario',
                  hintText: 'Ej. Lun–Sáb 8:00 a 21:00',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('rulesWelcome'),
                controller: _welcome,
                maxLines: 3,
                minLines: 2,
                maxLength: 160,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(color: AppColors.onSurface),
                decoration: const InputDecoration(
                  labelText: 'Mensaje de bienvenida',
                  hintText: 'Ej. ¡Hola! Pide aquí y te lo tenemos listo.',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  key: const Key('rulesSaveButton'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.emerald,
                    foregroundColor: AppColors.darkSlate,
                    disabledBackgroundColor: AppColors.surfaceVariant,
                    disabledForegroundColor: AppColors.onSurfaceMuted,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  onPressed: _valid ? _save : null,
                  child: const Text('Guardar reglas'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceMuted)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Switch(value: value, activeThumbColor: AppColors.emerald, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

class _MoneyField extends StatelessWidget {
  const _MoneyField({
    super.key,
    required this.controller,
    required this.label,
    required this.helper,
  });

  final TextEditingController controller;
  final String label;
  final String helper;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      style: const TextStyle(
        color: AppColors.onSurface,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
      decoration: InputDecoration(
        labelText: label,
        prefixText: '\$ ',
        suffixText: 'MXN',
        helperText: helper,
        helperMaxLines: 2,
        helperStyle: const TextStyle(fontSize: 11, color: AppColors.onSurfaceMuted),
      ),
    );
  }
}
