import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../domain/onboarding_state.dart';

// ---------------------------------------------------------------------------
// Contrato
// ---------------------------------------------------------------------------

abstract class OnboardingRepository {
  Future<OnboardingData> load();
  Future<void> save(OnboardingData data);
  Future<void> clear();
}

// ---------------------------------------------------------------------------
// Implementación Hive
// No requiere generación de código — usa mapa dinámico.
// Decisión D2: persistencia local sin backend (Alan Tarea 2.1 pendiente).
// ---------------------------------------------------------------------------

class OnboardingRepositoryHive implements OnboardingRepository {
  static const _boxName = 'nexus_onboarding';
  static const _dataKey = 'data';

  Future<Box> get _box async => Hive.isBoxOpen(_boxName)
      ? Hive.box(_boxName)
      : await Hive.openBox(_boxName);

  @override
  Future<OnboardingData> load() async {
    final box = await _box;
    final raw = box.get(_dataKey);
    if (raw == null) return const OnboardingData();
    return OnboardingData.fromMap(raw as Map);
  }

  @override
  Future<void> save(OnboardingData data) async {
    final box = await _box;
    await box.put(_dataKey, data.toMap());
  }

  @override
  Future<void> clear() async {
    final box = await _box;
    await box.delete(_dataKey);
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final onboardingRepositoryProvider = Provider<OnboardingRepository>(
  (_) => OnboardingRepositoryHive(),
);
