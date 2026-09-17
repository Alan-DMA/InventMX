import 'package:equatable/equatable.dart';

/// Configuración del catálogo del tenant — `CatalogSettingsResponse` del
/// backend real (`GET/PUT /catalog-settings`), más el `slug` que la vitrina
/// necesita para armar el enlace público.
///
/// Tarea 13.2.3 solo edita `isCatalogEnabled` y `whatsappNumber` (lo
/// indispensable para que un pedido llegue); el resto se muestra y se edita
/// después (WC-01 en `funcionalidades_pendientes_post_mvp.md`).
class CatalogSettings extends Equatable {
  const CatalogSettings({
    required this.slug,
    required this.storeName,
    this.isCatalogEnabled = true,
    this.whatsappNumber,
    this.welcomeMessage,
    this.minOrderAmountMxn = 0,
    this.deliveryFeeMxn = 0,
    this.deliveryEnabled = true,
    this.pickupEnabled = true,
    this.businessHours,
  });

  final String slug;
  final String storeName;
  final bool isCatalogEnabled;
  final String? whatsappNumber;
  final String? welcomeMessage;
  final double minOrderAmountMxn;
  final double deliveryFeeMxn;
  final bool deliveryEnabled;
  final bool pickupEnabled;
  final String? businessHours;

  bool get hasWhatsappNumber =>
      whatsappNumber != null && whatsappNumber!.trim().isNotEmpty;

  /// Los `String?` opcionales usan el patrón `Function()` para distinguir
  /// "no cambiar" (null) de "borrar" (`() => null`).
  CatalogSettings copyWith({
    bool? isCatalogEnabled,
    String? Function()? whatsappNumber,
    String? Function()? welcomeMessage,
    double? minOrderAmountMxn,
    double? deliveryFeeMxn,
    bool? deliveryEnabled,
    bool? pickupEnabled,
    String? Function()? businessHours,
  }) =>
      CatalogSettings(
        slug: slug,
        storeName: storeName,
        isCatalogEnabled: isCatalogEnabled ?? this.isCatalogEnabled,
        whatsappNumber:
            whatsappNumber == null ? this.whatsappNumber : whatsappNumber(),
        welcomeMessage:
            welcomeMessage == null ? this.welcomeMessage : welcomeMessage(),
        minOrderAmountMxn: minOrderAmountMxn ?? this.minOrderAmountMxn,
        deliveryFeeMxn: deliveryFeeMxn ?? this.deliveryFeeMxn,
        deliveryEnabled: deliveryEnabled ?? this.deliveryEnabled,
        pickupEnabled: pickupEnabled ?? this.pickupEnabled,
        businessHours:
            businessHours == null ? this.businessHours : businessHours(),
      );

  @override
  List<Object?> get props => [
        slug,
        storeName,
        isCatalogEnabled,
        whatsappNumber,
        welcomeMessage,
        minOrderAmountMxn,
        deliveryFeeMxn,
        deliveryEnabled,
        pickupEnabled,
        businessHours,
      ];
}

/// `nexus.com/tienda/abarrotes-don-pepe` a partir de "Abarrotes Don Pepe".
///
/// Mismo criterio que el backend usará para el slug del tenant: minúsculas,
/// sin acentos, solo letras/números, guiones en vez de espacios. En el mock
/// se deriva del nombre del onboarding; con backend real llega en la
/// configuración.
String slugify(String name) {
  const accents = {
    'á': 'a',
    'é': 'e',
    'í': 'i',
    'ó': 'o',
    'ú': 'u',
    'ü': 'u',
    'ñ': 'n',
    'à': 'a',
    'è': 'e',
    'ì': 'i',
    'ò': 'o',
    'ù': 'u',
  };
  final buffer = StringBuffer();
  for (final rune in name.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    buffer.write(accents[char] ?? char);
  }
  return buffer
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}
