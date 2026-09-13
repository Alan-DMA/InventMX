import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Firma de `launchUrl` — inyectada vía provider para poder sustituirla en
/// los tests de widget sin depender del canal de plataforma real.
typedef LaunchUrlFn = Future<bool> Function(Uri uri, {LaunchMode mode});

final urlLauncherProvider = Provider<LaunchUrlFn>((_) => launchUrl);

/// Solo dígitos — `tel:`/`wa.me` no aceptan espacios ni separadores.
String _digitsOnly(String phone) => phone.replaceAll(RegExp(r'[^\d+]'), '');

Uri callUri(String phone) => Uri.parse('tel:${_digitsOnly(phone)}');

Uri whatsAppUri(String phone) =>
    Uri.parse('https://wa.me/${_digitsOnly(phone).replaceAll('+', '')}');
