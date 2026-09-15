// Importación de Dio para peticiones HTTP
import 'package:dio/dio.dart';
// Importación de cimientos de Flutter para detección de plataforma
import 'package:flutter/foundation.dart';
// Importación de Riverpod para inyección de dependencias
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Importación del interceptor de autenticación
import '../storage/secure_storage.dart';
import 'auth_interceptor.dart';

///
/// Resuelve la URL base óptima para el entorno de desarrollo y pruebas.
/// Soporta Android Emulator (10.0.2.2), Web/Desktop (127.0.0.1) y override por compilación.
///
String getEffectiveApiBaseUrl() {
  // 1. Verificar si se proporcionó una URL explícita en tiempo de compilación
  const String envUrl = String.fromEnvironment('API_URL');
  // Si la variable de entorno no está vacía, utilizarla prioritariamente
  if (envUrl.isNotEmpty) {
    return envUrl;
  }

  // 2. Si se ejecuta en Flutter Web, resolver dinámicamente según el host del navegador
  if (kIsWeb) {
    final host = Uri.base.host;
    if (host.isNotEmpty) {
      return 'http://$host:8000';
    }
    return 'http://localhost:8000';
  }

  // 3. Si se ejecuta en Android (Emulador)
  if (defaultTargetPlatform == TargetPlatform.android) {
    // 10.0.2.2 redirige al localhost del equipo anfitrión
    return 'http://10.0.2.2:8000';
  }

  // 4. Por defecto para Windows Desktop, MacOS, Linux o entorno local
  return 'http://127.0.0.1:8000';
}

/// Proveedor global para la instancia de Dio
final dioProvider = Provider<Dio>((ref) {
  // Instanciación del cliente HTTP con opciones base
  final dio = Dio(
    BaseOptions(
      // Asignación de la URL base resuelta dinámicamente
      baseUrl: getEffectiveApiBaseUrl(),
      // Tiempo máximo de espera para conexión (10 segundos)
      connectTimeout: const Duration(seconds: 10),
      // Tiempo máximo de espera para recepción de respuesta (10 segundos)
      receiveTimeout: const Duration(seconds: 10),
      // Encabezados estándar para JSON
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ),
  );

  // Inyección del interceptor de autenticación JWT
  dio.interceptors.add(AuthInterceptor(
    storage: SecureStorage(),
    dio: dio,
  ));
  
  // Inyección de interceptor de logs durante desarrollo
  dio.interceptors.add(LogInterceptor(
    requestHeader: true,
    requestBody: true,
    responseHeader: false,
    responseBody: true,
    error: true,
  ));

  // Retorno de la instancia configurada
  return dio;
});
