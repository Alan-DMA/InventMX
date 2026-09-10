import 'package:equatable/equatable.dart';
import 'plan_option.dart';

/// Modelo de dominio del wizard de onboarding.
/// Persiste en Hive bajo la clave 'nexus_onboarding'.
class OnboardingData extends Equatable {
  const OnboardingData({
    this.businessName = '',
    this.logoPath,
    this.warehouseName = 'Almacén Principal',
    this.ticketHeader = '',
    this.selectedPlan = PlanOption.skipped,
    this.isCompleted = false,
  });

  /// Paso 1
  final String businessName;
  final String? logoPath; // path local de imagen (opcional)

  /// Paso 2
  final String warehouseName;
  final String ticketHeader;

  /// Paso 3
  final PlanOption selectedPlan;

  /// Flag persistido — si true, el wizard no se vuelve a mostrar
  final bool isCompleted;

  OnboardingData copyWith({
    String? businessName,
    String? logoPath,
    String? warehouseName,
    String? ticketHeader,
    PlanOption? selectedPlan,
    bool? isCompleted,
  }) {
    return OnboardingData(
      businessName: businessName ?? this.businessName,
      logoPath: logoPath ?? this.logoPath,
      warehouseName: warehouseName ?? this.warehouseName,
      ticketHeader: ticketHeader ?? this.ticketHeader,
      selectedPlan: selectedPlan ?? this.selectedPlan,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }

  /// Serialización para Hive (mapa simple, sin generación de código)
  Map<String, dynamic> toMap() => {
        'businessName': businessName,
        'logoPath': logoPath,
        'warehouseName': warehouseName,
        'ticketHeader': ticketHeader,
        'selectedPlan': selectedPlan.index,
        'isCompleted': isCompleted,
      };

  factory OnboardingData.fromMap(Map<dynamic, dynamic> map) {
    return OnboardingData(
      businessName: (map['businessName'] as String?) ?? '',
      logoPath: map['logoPath'] as String?,
      warehouseName:
          (map['warehouseName'] as String?) ?? 'Almacén Principal',
      ticketHeader: (map['ticketHeader'] as String?) ?? '',
      selectedPlan: PlanOption.values[
          (map['selectedPlan'] as int?) ?? PlanOption.skipped.index],
      isCompleted: (map['isCompleted'] as bool?) ?? false,
    );
  }

  @override
  List<Object?> get props => [
        businessName,
        logoPath,
        warehouseName,
        ticketHeader,
        selectedPlan,
        isCompleted,
      ];
}
