import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/supplier.dart';
import 'phone_launcher.dart';

/// Fila del Directorio de Proveedores — Subtarea 11.2.2, Figma tab
/// "Proveedores": nombre, teléfono con acceso directo a llamada/WhatsApp.
class SupplierListTile extends ConsumerWidget {
  const SupplierListTile({
    super.key,
    required this.supplier,
    required this.onTap,
  });

  final Supplier supplier;
  final VoidCallback onTap;

  Future<void> _launch(WidgetRef ref, BuildContext context, Uri uri) async {
    final messenger = ScaffoldMessenger.of(context);
    final launch = ref.read(urlLauncherProvider);
    final ok = await launch(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo abrir la aplicación.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phone = supplier.phone;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.emerald.withValues(alpha: 0.15),
              child: Text(
                supplier.name.isNotEmpty ? supplier.name[0].toUpperCase() : '?',
                style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.emerald),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    supplier.name,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.onSurface),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    phone ?? 'Sin teléfono registrado',
                    style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted),
                  ),
                ],
              ),
            ),
            if (phone != null) ...[
              _ActionButton(
                icon: Icons.call_rounded,
                color: AppColors.skyBlue,
                tooltip: 'Llamar',
                onTap: () => _launch(ref, context, callUri(phone)),
              ),
              const SizedBox(width: 8),
              _ActionButton(
                icon: Icons.chat_rounded,
                color: AppColors.success,
                tooltip: 'WhatsApp',
                onTap: () => _launch(ref, context, whatsAppUri(phone)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Icon(icon, size: 18, color: color),
          ),
        ),
      ),
    );
  }
}
