import 'dart:convert';
import 'package:flutter/material.dart';
import '../network/api_client.dart';
import '../theme/app_colors.dart';

/// Widget unificado para renderizar imágenes de productos en Nexus.
///
/// Soporta:
/// 1. Binarios embebidos en Base64 ('data:image/png;base64,...') almacenados directamente en PostgreSQL.
/// 2. URLs absolutas remotas ('http://...', 'https://...').
/// 3. Rutas relativas del servidor Nexus ('/uploads/images/...').
/// 4. Fallback visual automático con placeholder si la imagen es nula o falla.
class ProductImageWidget extends StatelessWidget {
  const ProductImageWidget({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholder,
  });

  final String? imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? placeholder;

  Widget _buildPlaceholder() {
    if (placeholder != null) return placeholder!;
    return Container(
      width: width,
      height: height,
      color: AppColors.surfaceVariant,
      child: Center(
        child: Icon(
          Icons.inventory_2_outlined,
          size: (width != null && width! < 60) ? 22 : 36,
          color: AppColors.onSurfaceMuted.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.trim().isEmpty) {
      return _buildPlaceholder();
    }

    final raw = imageUrl!.trim();

    Widget imageWidget;

    // Caso 1: Binario en formato Data URI Base64 (almacenado en BD)
    if (raw.startsWith('data:image')) {
      try {
        final commaIndex = raw.indexOf(',');
        final base64Data =
            commaIndex != -1 ? raw.substring(commaIndex + 1) : raw;
        final bytes = base64Decode(base64Data);
        imageWidget = Image.memory(
          bytes,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (_, __, ___) => _buildPlaceholder(),
        );
      } catch (_) {
        imageWidget = _buildPlaceholder();
      }
    } else {
      // Caso 2 & 3: URL absoluta o ruta relativa al servidor
      String fullUrl = raw;
      if (!raw.startsWith('http://') && !raw.startsWith('https://')) {
        final base = getEffectiveApiBaseUrl();
        fullUrl = '$base${raw.startsWith('/') ? raw : '/$raw'}';
      }

      imageWidget = Image.network(
        fullUrl,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => _buildPlaceholder(),
      );
    }

    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius!,
        child: imageWidget,
      );
    }

    return imageWidget;
  }
}
