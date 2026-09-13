// DTOs fuertemente tipados para administración de respaldos y copias de seguridad (Día 16 / HU-25 / CU-31)
// Moneda base nativa: Pesos Mexicanos ($ MXN)
// Comentarios exhaustivos línea por línea según .agents/AGENTS.md

/// Enumeración de tipos de respaldo admitidos
enum BackupType {
  /// Respaldo completo de esquemas y datos
  full,
  /// Respaldo únicamente de definiciones de esquemas DDL
  schemaOnly,
  /// Respaldo únicamente de registros transaccionales
  dataOnly;

  /// Conversión desde string de la API
  static BackupType fromString(String value) {
    switch (value.toUpperCase()) {
      case 'FULL':
        return BackupType.full;
      case 'SCHEMA_ONLY':
        return BackupType.schemaOnly;
      case 'DATA_ONLY':
        return BackupType.dataOnly;
      default:
        return BackupType.full;
    }
  }

  /// Conversión a string de la API
  String toApiString() {
    switch (this) {
      case BackupType.full:
        return 'FULL';
      case BackupType.schemaOnly:
        return 'SCHEMA_ONLY';
      case BackupType.dataOnly:
        return 'DATA_ONLY';
    }
  }
}

/// Enumeración de estados de ejecución de respaldos
enum BackupStatus {
  /// Respaldo en proceso de generación
  pending,
  /// Respaldo generado y verificado exitosamente
  completed,
  /// Respaldo fallido
  failed;

  /// Conversión desde string de la API
  static BackupStatus fromString(String value) {
    switch (value.toUpperCase()) {
      case 'PENDING':
        return BackupStatus.pending;
      case 'COMPLETED':
        return BackupStatus.completed;
      case 'FAILED':
        return BackupStatus.failed;
      default:
        return BackupStatus.pending;
    }
  }

  /// Conversión a string de la API
  String toApiString() {
    switch (this) {
      case BackupStatus.pending:
        return 'PENDING';
      case BackupStatus.completed:
        return 'COMPLETED';
      case BackupStatus.failed:
        return 'FAILED';
    }
  }
}

/// Proveedor de almacenamiento en la nube
enum StorageProvider {
  /// Almacenamiento local en disco
  local,
  /// Cloudflare R2 Object Storage
  cloudflareR2,
  /// Backblaze B2 Object Storage
  backblazeB2,
  /// Amazon Web Services S3
  awsS3;

  /// Conversión desde string de la API
  static StorageProvider fromString(String value) {
    switch (value.toUpperCase()) {
      case 'LOCAL':
        return StorageProvider.local;
      case 'CLOUDFLARE_R2':
        return StorageProvider.cloudflareR2;
      case 'BACKBLAZE_B2':
        return StorageProvider.backblazeB2;
      case 'AWS_S3':
        return StorageProvider.awsS3;
      default:
        return StorageProvider.cloudflareR2;
    }
  }

  /// Conversión a string de la API
  String toApiString() {
    switch (this) {
      case StorageProvider.local:
        return 'LOCAL';
      case StorageProvider.cloudflareR2:
        return 'CLOUDFLARE_R2';
      case StorageProvider.backblazeB2:
        return 'BACKBLAZE_B2';
      case StorageProvider.awsS3:
        return 'AWS_S3';
    }
  }
}

/// DTO de solicitud para creación de un nuevo respaldo
class BackupCreateRequestDto {
  /// Tipo de respaldo
  final BackupType backupType;
  /// Indicador si incluye todos los tenants
  final bool includeAllTenants;
  /// Notas descriptivas
  final String? notes;

  /// Constructor inmutable
  const BackupCreateRequestDto({
    this.backupType = BackupType.full,
    this.includeAllTenants = true,
    this.notes,
  });

  /// Serialización a mapa JSON para la petición HTTP
  Map<String, dynamic> toJson() {
    return {
      'backup_type': backupType.toApiString(),
      'include_all_tenants': includeAllTenants,
      'notes': notes,
    };
  }
}

/// DTO con los metadatos de un archivo de respaldo generado
class BackupMetadataDto {
  /// Identificador único
  final String id;
  /// Nombre del archivo comprimido
  final String filename;
  /// Tipo de respaldo
  final BackupType backupType;
  /// Estado de ejecución
  final BackupStatus status;
  /// Tamaño en bytes
  final int sizeBytes;
  /// Checksum SHA-256 para verificación de integridad
  final String sha256Checksum;
  /// Proveedor de almacenamiento
  final StorageProvider storageProvider;
  /// Fecha de creación
  final DateTime createdAt;
  /// Fecha de expiración (política de 30 días)
  final DateTime expiresAt;
  /// Cantidad de tablas respaldadas
  final int tablesCount;
  /// Cantidad de registros respaldados
  final int recordsCount;
  /// Notas explicativas
  final String? notes;

  /// Constructor inmutable
  const BackupMetadataDto({
    required this.id,
    required this.filename,
    required this.backupType,
    required this.status,
    required this.sizeBytes,
    required this.sha256Checksum,
    required this.storageProvider,
    required this.createdAt,
    required this.expiresAt,
    required this.tablesCount,
    required this.recordsCount,
    this.notes,
  });

  /// Deserialización segura desde JSON
  factory BackupMetadataDto.fromJson(Map<String, dynamic> json) {
    return BackupMetadataDto(
      id: json['id'] as String? ?? '',
      filename: json['filename'] as String? ?? '',
      backupType: BackupType.fromString(json['backup_type'] as String? ?? 'FULL'),
      status: BackupStatus.fromString(json['status'] as String? ?? 'PENDING'),
      sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
      sha256Checksum: json['sha256_checksum'] as String? ?? '',
      storageProvider: StorageProvider.fromString(json['storage_provider'] as String? ?? 'CLOUDFLARE_R2'),
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'] as String) : DateTime.now(),
      expiresAt: json['expires_at'] != null ? DateTime.parse(json['expires_at'] as String) : DateTime.now(),
      tablesCount: (json['tables_count'] as num?)?.toInt() ?? 0,
      recordsCount: (json['records_count'] as num?)?.toInt() ?? 0,
      notes: json['notes'] as String?,
    );
  }

  /// Tamaño formateado amigable (KB, MB, GB)
  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    if (sizeBytes < 1024 * 1024 * 1024) return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// DTO con la lista de respaldos disponibles y consumo de cuota
class BackupListDto {
  /// Total de respaldos activos
  final int totalBackups;
  /// Tamaño total acumulado en bytes
  final int totalSizeBytes;
  /// Días de la política de retención
  final int retentionPolicyDays;
  /// Lista de metadatos de respaldos
  final List<BackupMetadataDto> backups;

  /// Constructor inmutable
  const BackupListDto({
    required this.totalBackups,
    required this.totalSizeBytes,
    required this.retentionPolicyDays,
    required this.backups,
  });

  /// Deserialización segura desde JSON
  factory BackupListDto.fromJson(Map<String, dynamic> json) {
    return BackupListDto(
      totalBackups: (json['total_backups'] as num?)?.toInt() ?? 0,
      totalSizeBytes: (json['total_size_bytes'] as num?)?.toInt() ?? 0,
      retentionPolicyDays: (json['retention_policy_days'] as num?)?.toInt() ?? 30,
      backups: (json['backups'] as List<dynamic>?)
              ?.map((item) => BackupMetadataDto.fromJson(item as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}
