/// Planes de suscripción oficiales de Nexus v3.0-MX.
/// Constitución Art. VI §6.1 — Estructura de Planes en Pesos Mexicanos.
/// No existe un tier gratuito permanente; el botón "Omitir" asigna SKIPPED
/// y el sistema otorga acceso temporal (trial 14 días por defecto).
enum PlanOption {
  emprendedor, // $199 MXN/mes — hasta 2 usuarios, 1 almacén
  comercio, // $399 MXN/mes — hasta 5 usuarios, multi-almacén
  corporativo, // $699 MXN/mes — hasta 15 usuarios, todos los módulos
  skipped, // Usuario omitió la selección — trial corto por defecto
}

extension PlanOptionX on PlanOption {
  String get label {
    switch (this) {
      case PlanOption.emprendedor:
        return 'Emprendedor';
      case PlanOption.comercio:
        return 'Comercio';
      case PlanOption.corporativo:
        return 'Corporativo';
      case PlanOption.skipped:
        return 'Sin seleccionar';
    }
  }

  /// Precio mensual en MXN (0 = sin selección)
  int get priceMxn {
    switch (this) {
      case PlanOption.emprendedor:
        return 199;
      case PlanOption.comercio:
        return 399;
      case PlanOption.corporativo:
        return 699;
      case PlanOption.skipped:
        return 0;
    }
  }

  /// Subtítulo que aparece en la pantalla de éxito (Paso 4).
  String get successSubtitle {
    switch (this) {
      case PlanOption.emprendedor:
        return 'Tu prueba gratuita de 14 días ya comenzó.';
      case PlanOption.comercio:
        return 'Tu prueba gratuita de 14 días ya comenzó.';
      case PlanOption.corporativo:
        return 'Tu prueba gratuita de 14 días ya comenzó.';
      case PlanOption.skipped:
        return 'Puedes elegir un plan en cualquier momento desde tu perfil.';
    }
  }

  /// Texto del estado de cuenta en la pantalla de éxito.
  String get successAccountStatus {
    switch (this) {
      case PlanOption.skipped:
        return 'Sin plan seleccionado';
      default:
        return 'Plan $label (Prueba de 14 días activa)';
    }
  }
}
