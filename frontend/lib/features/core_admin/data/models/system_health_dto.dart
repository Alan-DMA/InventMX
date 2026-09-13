// DTOs fuertemente tipados para monitoreo de salud del sistema y diagnóstico operativo (Día 16 / HU-25 / CU-31)
// Comentarios exhaustivos línea por línea según .agents/AGENTS.md

/// DTO con el diagnóstico de salud y métricas del sistema Nexus v3
class SystemHealthCheckDto {
  /// Estado global (healthy, degraded, unhealthy)
  final String status;
  /// Indicador de conexión a PostgreSQL
  final bool databaseConnected;
  /// Latencia de respuesta en milisegundos
  final double databaseLatencyMs;
  /// Confirmación de aislamiento Row-Level Security activo
  final bool rlsEnforced;
  /// Versión del sistema
  final String version;
  /// Estampa de tiempo del diagnóstico
  final DateTime timestamp;
  /// Entorno de despliegue (production, staging, development)
  final String environment;
  /// Cantidad total de comercios activos
  final int activeTenantsCount;
  /// Total de productos en inventario
  final int totalProductsCount;
  /// Total de ventas procesadas
  final int totalSalesCount;

  /// Constructor inmutable
  const SystemHealthCheckDto({
    required this.status,
    required this.databaseConnected,
    required this.databaseLatencyMs,
    required this.rlsEnforced,
    required this.version,
    required this.timestamp,
    required this.environment,
    required this.activeTenantsCount,
    required this.totalProductsCount,
    required this.totalSalesCount,
  });

  /// Deserialización segura desde JSON
  factory SystemHealthCheckDto.fromJson(Map<String, dynamic> json) {
    return SystemHealthCheckDto(
      status: json['status'] as String? ?? 'unknown',
      databaseConnected: json['database_connected'] as bool? ?? false,
      databaseLatencyMs: (json['database_latency_ms'] as num?)?.toDouble() ?? 0.0,
      rlsEnforced: json['rls_enforced'] as bool? ?? true,
      version: json['version'] as String? ?? '3.0.0',
      timestamp: json['timestamp'] != null ? DateTime.parse(json['timestamp'] as String) : DateTime.now(),
      environment: json['environment'] as String? ?? 'development',
      activeTenantsCount: (json['active_tenants_count'] as num?)?.toInt() ?? 0,
      totalProductsCount: (json['total_products_count'] as num?)?.toInt() ?? 0,
      totalSalesCount: (json['total_sales_count'] as num?)?.toInt() ?? 0,
    );
  }

  /// Determina si el sistema está completamente operativo
  bool get isHealthy => status == 'healthy' && databaseConnected && rlsEnforced;
}
