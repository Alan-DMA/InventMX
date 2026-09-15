import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/catalog_config.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../purchases/presentation/widgets/phone_launcher.dart';
import '../domain/catalog_settings.dart';
import 'whatsapp_catalog_provider.dart';

/// Panel de difusión del tendero — Tarea 13.2.3 (RF-27).
///
/// Vive dentro de la app (tema oscuro) y responde tres preguntas en el
/// orden en que el tendero las hace: ¿está prendido y a qué número llegan
/// los pedidos?, ¿cuál es mi enlace?, ¿cómo lo comparto? (copiar, WhatsApp,
/// QR para el mostrador).
///
/// Solo edita lo indispensable para que un pedido llegue: el switch y el
/// número. El resto de la configuración (mínimo, envío, horario) es WC-01.
class CatalogShareScreen extends ConsumerStatefulWidget {
  const CatalogShareScreen({super.key});

  @override
  ConsumerState<CatalogShareScreen> createState() => _CatalogShareScreenState();
}

class _CatalogShareScreenState extends ConsumerState<CatalogShareScreen> {
  final _qrKey = GlobalKey();
  bool _sharingQr = false;

  Future<void> _copyLink(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Enlace copiado'),
      behavior: SnackBarBehavior.floating,
    ));
  }

  /// Abre WhatsApp con el mensaje listo para pegar en un chat o un estado;
  /// si no hay WhatsApp, la hoja de compartir del sistema.
  Future<void> _shareOnWhatsApp(CatalogSettings settings, String url) async {
    final text = 'Mira mi catálogo de ${settings.storeName} y haz tu pedido '
        'por WhatsApp: $url';
    final uri = Uri.https('wa.me', '/', {'text': text});
    final opened = await ref.read(urlLauncherProvider)(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened) await Share.share(text, subject: settings.storeName);
  }

  Future<void> _shareQr(CatalogSettings settings) async {
    setState(() => _sharingQr = true);
    try {
      final boundary =
          _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/qr_catalogo_${settings.slug}.png');
      await file.writeAsBytes(bytes.buffer.asUint8List());
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        subject: 'QR del catálogo de ${settings.storeName}',
      );
    } finally {
      if (mounted) setState(() => _sharingQr = false);
    }
  }

  Future<void> _editNumber(CatalogSettings settings) async {
    final number = await showDialog<String>(
      context: context,
      builder: (_) => _NumberDialog(initial: settings.whatsappNumber ?? ''),
    );
    if (number == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(catalogSettingsProvider.notifier)
          .setWhatsappNumber(number);
      messenger.showSnackBar(const SnackBar(
        content: Text('Número guardado'),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
        content: Text('No se pudo guardar el número. Inténtalo de nuevo.'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _toggle(bool enabled) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(catalogSettingsProvider.notifier).setEnabled(enabled);
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
        content: Text('No se pudo cambiar el estado del catálogo.'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(catalogSettingsProvider);

    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      appBar: AppBar(
        backgroundColor: AppColors.darkSlate,
        title: const Text('Mi catálogo'),
      ),
      body: settings.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.emerald),
        ),
        error: (_, __) => _ErrorState(
          onRetry: () => ref.invalidate(catalogSettingsProvider),
        ),
        data: (data) {
          final url = publicCatalogUrl(data.slug);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              _StatusCard(
                settings: data,
                saving: settings.isLoading,
                onToggle: _toggle,
                onEditNumber: () => _editNumber(data),
              ),
              const SizedBox(height: 16),
              _LinkCard(
                url: url,
                onCopy: () => _copyLink(url),
                onWhatsApp: () => _shareOnWhatsApp(data, url),
                onPreview: () =>
                    context.push(AppRoutes.publicCatalogPath(data.slug)),
              ),
              const SizedBox(height: 16),
              _QrCard(
                qrKey: _qrKey,
                url: url,
                storeName: data.storeName,
                sharing: _sharingQr,
                onShare: () => _shareQr(data),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tarjetas
// ---------------------------------------------------------------------------

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.settings,
    required this.saving,
    required this.onToggle,
    required this.onEditNumber,
  });

  final CatalogSettings settings;
  final bool saving;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEditNumber;

  @override
  Widget build(BuildContext context) {
    final enabled = settings.isCatalogEnabled;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      enabled ? 'Catálogo activo' : 'Catálogo apagado',
                      key: const Key('catalogStatusTitle'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      enabled
                          ? 'Tus clientes ven tus productos y precios de hoy.'
                          : 'Quien abra tu enlace verá que está apagado.',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.onSurfaceMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                key: const Key('catalogEnabledSwitch'),
                value: enabled,
                activeThumbColor: AppColors.emerald,
                onChanged: saving ? null : onToggle,
              ),
            ],
          ),
          const Divider(height: 24),
          Row(
            children: [
              Icon(
                settings.hasWhatsappNumber
                    ? Icons.chat_outlined
                    : Icons.phone_disabled_outlined,
                size: 18,
                color: settings.hasWhatsappNumber
                    ? AppColors.onSurfaceMuted
                    : AppColors.warning,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  settings.hasWhatsappNumber
                      ? 'Los pedidos llegan al ${settings.whatsappNumber}'
                      : 'Falta tu número de WhatsApp: sin él, nadie puede '
                          'mandarte pedidos.',
                  key: const Key('catalogNumberText'),
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: settings.hasWhatsappNumber
                        ? AppColors.onSurface
                        : AppColors.warning,
                  ),
                ),
              ),
              TextButton(
                key: const Key('catalogEditNumber'),
                onPressed: onEditNumber,
                child: Text(settings.hasWhatsappNumber ? 'Cambiar' : 'Agregar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LinkCard extends StatelessWidget {
  const _LinkCard({
    required this.url,
    required this.onCopy,
    required this.onWhatsApp,
    required this.onPreview,
  });

  final String url;
  final VoidCallback onCopy;
  final VoidCallback onWhatsApp;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tu enlace',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.darkSlate,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    url,
                    key: const Key('catalogLink'),
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: AppColors.skyBlue,
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('catalogCopyLink'),
                  tooltip: 'Copiar enlace',
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy_rounded,
                      size: 20, color: AppColors.onSurface),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            key: const Key('catalogShareWhatsApp'),
            onPressed: onWhatsApp,
            icon: const Icon(Icons.share_rounded, size: 18),
            label: const Text('Compartir por WhatsApp'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('catalogPreview'),
            onPressed: onPreview,
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: const Text('Ver como cliente'),
          ),
        ],
      ),
    );
  }
}

class _QrCard extends StatelessWidget {
  const _QrCard({
    required this.qrKey,
    required this.url,
    required this.storeName,
    required this.sharing,
    required this.onShare,
  });

  final GlobalKey qrKey;
  final String url;
  final String storeName;
  final bool sharing;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'QR para el mostrador',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Imprímelo y pégalo junto a la caja: tus clientes lo escanean y '
            'piden desde su celular.',
            style: TextStyle(fontSize: 12.5, color: AppColors.onSurfaceMuted),
          ),
          const SizedBox(height: 14),
          Center(
            // Lo que se comparte es exactamente esto: QR + nombre + enlace,
            // sobre blanco para que cualquier impresora lo saque legible.
            child: RepaintBoundary(
              key: qrKey,
              child: Container(
                width: 240,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                color: Colors.white,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    QrImageView(
                      key: const Key('catalogQr'),
                      data: url,
                      size: 200,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Color(0xFF111827),
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      storeName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const Text(
                      'Escanea y haz tu pedido por WhatsApp',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            key: const Key('catalogShareQr'),
            onPressed: sharing ? null : onShare,
            icon: sharing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.print_outlined, size: 18),
            label: const Text('Compartir o imprimir el QR'),
          ),
        ],
      ),
    );
  }
}

class _NumberDialog extends StatefulWidget {
  const _NumberDialog({required this.initial});

  final String initial;

  @override
  State<_NumberDialog> createState() => _NumberDialogState();
}

class _NumberDialogState extends State<_NumberDialog> {
  late final _ctrl = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _save() {
    final digits = _ctrl.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10) {
      setState(() => _error = 'Escribe los 10 dígitos de tu WhatsApp.');
      return;
    }
    Navigator.of(context).pop(_ctrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('WhatsApp para pedidos'),
      content: TextField(
        key: const Key('catalogNumberField'),
        controller: _ctrl,
        autofocus: true,
        keyboardType: TextInputType.phone,
        onChanged: (_) => setState(() => _error = null),
        onSubmitted: (_) => _save(),
        decoration: InputDecoration(
          hintText: '+52 55 1234 5678',
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          key: const Key('catalogNumberSave'),
          onPressed: _save,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off_rounded,
                size: 40, color: AppColors.onSurfaceMuted),
            const SizedBox(height: 12),
            const Text(
              'No se pudo cargar tu catálogo',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
                onPressed: onRetry, child: const Text('Intentar de nuevo')),
          ],
        ),
      ),
    );
  }
}
