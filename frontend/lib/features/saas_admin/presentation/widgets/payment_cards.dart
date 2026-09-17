import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/barcode_painter.dart';
import '../../domain/subscription.dart';

/// Tarjetas de pago de la suscripción — Tarea 14.2.1.
///
/// Un dato por fila, en cifras tabulares, con su propio "Copiar": el tendero
/// coteja contra la banca móvil dato por dato. El monto aparece aquí una
/// sola vez, exacto, junto a la CLABE y el concepto (sin costos escondidos).

const _tabular = [FontFeature.tabularFigures()];

/// Fila etiqueta · valor · copiar. `mono` agrupa dígitos (CLABE, referencia).
class CopyRow extends StatelessWidget {
  const CopyRow({
    super.key,
    required this.label,
    required this.value,
    required this.copyValue,
    this.mono = false,
    this.emphasis = false,
    this.copyKey,
  });

  final String label;
  final String value;

  /// Lo que va al portapapeles (sin espacios de agrupación).
  final String copyValue;
  final bool mono;
  final bool emphasis;
  final Key? copyKey;

  Future<void> _copy(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: copyValue));
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text('$label copiado'),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.onSurfaceMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: emphasis ? 20 : 16,
                    fontWeight: emphasis ? FontWeight.w800 : FontWeight.w600,
                    color: AppColors.onSurface,
                    fontFeatures: _tabular,
                    letterSpacing: mono ? 0.6 : 0,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              key: copyKey,
              onPressed: () => _copy(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.onSurface,
                side: const BorderSide(color: AppColors.border),
                // El tema fuerza minimumSize infinito (botones a todo el ancho).
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('Copiar', style: TextStyle(fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Instrucciones SPEI: CLABE fija de Nexus + concepto = código del comercio.
class SpeiInstructionsCard extends StatelessWidget {
  const SpeiInstructionsCard({super.key, required this.spei});

  final SpeiInstructions spei;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      title: 'Transferencia SPEI',
      subtitle:
          'Desde tu banca móvil. Se acredita en minutos; nosotros lo validamos.',
      child: Column(
        children: [
          CopyRow(
            label: 'CLABE',
            value: spei.clabeGrouped,
            copyValue: spei.clabe,
            mono: true,
            copyKey: const Key('copyClabe'),
          ),
          const Divider(height: 8, color: AppColors.border),
          CopyRow(
            label: 'Monto exacto',
            value: '${mxn(spei.amountMxn)} MXN',
            copyValue: spei.amountMxn.toStringAsFixed(2),
            emphasis: true,
            copyKey: const Key('copyAmount'),
          ),
          const Divider(height: 8, color: AppColors.border),
          CopyRow(
            label: 'Concepto',
            value: spei.concept,
            copyValue: spei.concept,
            mono: true,
            copyKey: const Key('copyConcept'),
          ),
          const Divider(height: 8, color: AppColors.border),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                _kv('Banco', spei.bank),
                const SizedBox(width: 16),
                _kv('Beneficiario', spei.holder),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(k,
                style: const TextStyle(
                    fontSize: 11.5, color: AppColors.onSurfaceMuted)),
            const SizedBox(height: 2),
            Text(v,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface,
                )),
          ],
        ),
      );
}

/// Referencia OXXO: código numérico + barras. Si el backend no la entrega
/// (sin proveedor en el MVP), se dice sin rodeos.
class OxxoInstructionsCard extends StatelessWidget {
  const OxxoInstructionsCard(
      {super.key, required this.oxxo, required this.amountMxn});

  final OxxoInstructions? oxxo;
  final double amountMxn;

  @override
  Widget build(BuildContext context) {
    final o = oxxo;
    if (o == null) {
      return const _CardShell(
        title: 'Pago en OXXO',
        subtitle: 'Disponible próximamente.',
        child: Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text(
            'Todavía no generamos referencias para OXXO. Por ahora paga por '
            'transferencia SPEI; si solo puedes pagar en efectivo, avísanos '
            'con "Ya pagué" y elige "Efectivo".',
            key: Key('oxxoUnavailable'),
            style: TextStyle(
                fontSize: 13.5, color: AppColors.onSurfaceMuted, height: 1.4),
          ),
        ),
      );
    }

    return _CardShell(
      title: 'Pago en OXXO',
      subtitle:
          'Muestra este código en caja. Vigente hasta el ${longDate(o.expiresAt)}.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 6),
          // Fondo blanco: las barras se escanean sobre papel, no sobre slate.
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                SizedBox(
                  height: 56,
                  child: CustomPaint(
                    key: const Key('oxxoBarcode'),
                    painter: BarcodePainter(
                        code: o.barcode, color: const Color(0xFF111827)),
                    size: Size.infinite,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  o.referenceGrouped,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                    fontFeatures: _tabular,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          CopyRow(
            label: 'Referencia',
            value: o.referenceGrouped,
            copyValue: o.reference,
            mono: true,
            copyKey: const Key('copyOxxoReference'),
          ),
          const Divider(height: 8, color: AppColors.border),
          CopyRow(
            label: 'Monto exacto',
            value: '${mxn(amountMxn)} MXN',
            copyValue: amountMxn.toStringAsFixed(2),
            emphasis: true,
          ),
        ],
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell(
      {required this.title, required this.subtitle, required this.child});

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
                fontSize: 12.5, color: AppColors.onSurfaceMuted, height: 1.35),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}
