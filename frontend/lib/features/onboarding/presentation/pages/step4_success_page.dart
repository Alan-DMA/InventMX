import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/router/app_router.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../domain/onboarding_state.dart';
import '../../domain/plan_option.dart';
import '../onboarding_provider.dart';

// ---------------------------------------------------------------------------
// Paso 4 — Pantalla de Éxito
//
// Fixes aplicados (Bug Tarea 2.2):
//   1. Consistencia visual: Scaffold con fondo darkSlate explícito + AppBar
//      con mismo estilo que el wizard shell (idéntico a los pasos 1-3).
//   2. Sin auto-redirect: se eliminó el Future.delayed(4s). La navegación
//      ocurre ÚNICAMENTE al presionar el botón.
//   3. Botón renombrado: "Ir al Dashboard →"  →  "Comenzar  →"
//   4. Confeti: animación pura en Flutter (cero dependencias externas).
//      Cumple Constitución Art. IV (Bootstrap — sin librerías innecesarias).
// ---------------------------------------------------------------------------

/// Modelo de una partícula de confeti.
class _ConfettiParticle {
  final double x; // posición horizontal inicial (0..1 normalizada)
  final double size; // tamaño del cuadrado
  final Color color;
  final double speed; // velocidad de caída (px / tick normalizado)
  final double drift; // deriva horizontal por tick
  final double angle; // ángulo de rotación inicial (rad)
  final double spin; // velocidad de rotación (rad / tick)

  const _ConfettiParticle({
    required this.x,
    required this.size,
    required this.color,
    required this.speed,
    required this.drift,
    required this.angle,
    required this.spin,
  });
}

/// Genera [count] partículas con valores aleatorios.
List<_ConfettiParticle> _generateParticles(int count) {
  final rng = Random();
  const palette = [
    AppColors.emerald,
    AppColors.skyBlue,
    Color(0xFFF59E0B), // warning amber
    Color(0xFFEF4444), // error red
    Color(0xFFA78BFA), // violet
    Color(0xFFFBBF24), // yellow
  ];

  return List.generate(count, (_) {
    return _ConfettiParticle(
      x: rng.nextDouble(),
      size: 5 + rng.nextDouble() * 7,
      color: palette[rng.nextInt(palette.length)],
      speed: 0.003 + rng.nextDouble() * 0.004,
      drift: (rng.nextDouble() - 0.5) * 0.002,
      angle: rng.nextDouble() * pi * 2,
      spin: (rng.nextDouble() - 0.5) * 0.15,
    );
  });
}

/// Painter que dibuja las partículas en su posición actual.
class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiParticle> particles;
  final double progress; // 0.0 → 1.0

  const _ConfettiPainter({
    required this.particles,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final y = size.height * progress * p.speed * 300;
      final x = p.x * size.width + p.drift * size.width * progress * 300;
      // Sólo pinta mientras la partícula está dentro del viewport
      if (y > size.height + p.size) continue;

      final paint = Paint()..color = p.color.withValues(alpha: 0.85);
      final currentAngle = p.angle + p.spin * progress * 300;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(currentAngle);
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: p.size,
          height: p.size * 0.6,
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.progress != progress;
}

// ---------------------------------------------------------------------------
// Widget principal
// ---------------------------------------------------------------------------

class Step4SuccessPage extends ConsumerStatefulWidget {
  const Step4SuccessPage({super.key});

  @override
  ConsumerState<Step4SuccessPage> createState() => _Step4SuccessPageState();
}

class _Step4SuccessPageState extends ConsumerState<Step4SuccessPage>
    with TickerProviderStateMixin {
  // -- checkmark --
  late final AnimationController _checkController;
  late final Animation<double> _checkScale;

  // -- contenido --
  late final AnimationController _contentController;
  late final Animation<double> _contentFade;

  // -- confeti --
  late final AnimationController _confettiController;
  late final List<_ConfettiParticle> _particles;

  @override
  void initState() {
    super.initState();

    // Checkmark: escala 0 → 1.2 → 1.0
    _checkController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _checkScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.2), weight: 60),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0), weight: 40),
    ]).animate(CurvedAnimation(
      parent: _checkController,
      curve: Curves.easeOut,
    ));

    // Contenido: fade-in tras el checkmark
    _contentController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _contentFade = CurvedAnimation(
      parent: _contentController,
      curve: Curves.easeIn,
    );

    // Confeti: 2.5 s de lluvia, sin loop
    _confettiController = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    );
    _particles = _generateParticles(80);

    // Secuencia: checkmark → contenido + confeti simultáneos
    _checkController.forward().then((_) {
      _contentController.forward();
      _confettiController.forward();
    });

    // ⚠️ NO hay Future.delayed ni auto-redirect.
    // La navegación ocurre SOLO al pulsar el botón.
  }

  @override
  void dispose() {
    _checkController.dispose();
    _contentController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ Navegación

  Future<void> _navigateToDashboard() async {
    if (!mounted) return;
    await ref.read(onboardingProvider.notifier).completeOnboarding();
    if (mounted) context.go(AppRoutes.dashboard);
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(onboardingProvider).data;
    final isSaving = ref.watch(onboardingProvider).isSaving;
    final businessName =
        data.businessName.isEmpty ? 'Tu tienda' : data.businessName;

    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      // AppBar idéntico al del wizard shell para uniformidad visual
      appBar: AppBar(
        backgroundColor: AppColors.darkSlate,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: const Column(
          children: [
            Text(
              'Nexus Express',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
            ),
            Text(
              'Setup completado',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: AppColors.onSurfaceMuted,
              ),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          // ── Capa de confeti (sobre el fondo, debajo del contenido) ──
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _confettiController,
              builder: (_, __) => CustomPaint(
                painter: _ConfettiPainter(
                  particles: _particles,
                  progress: _confettiController.value,
                ),
              ),
            ),
          ),

          // ── Contenido principal ──
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 40),
                  _buildCheckmark(),
                  const SizedBox(height: 24),
                  _buildTitle(context, businessName),
                  const SizedBox(height: 32),
                  FadeTransition(
                    opacity: _contentFade,
                    child: Column(
                      children: [
                        _buildSummaryCard(data),
                        const SizedBox(height: 16),
                        _buildTipCard(context),
                        const SizedBox(height: 32),
                        _buildCta(isSaving),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────── Checkmark ───────────────────────────────────

  Widget _buildCheckmark() {
    return ScaleTransition(
      scale: _checkScale,
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          color: AppColors.emerald.withValues(alpha: 0.15),
          shape: BoxShape.circle,
          border: Border.all(
            color: AppColors.emerald.withValues(alpha: 0.35),
            width: 2,
          ),
        ),
        child: const Icon(
          Icons.check_circle_rounded,
          size: 56,
          color: AppColors.emerald,
        ),
      ),
    );
  }

  // ─────────────────────────── Título ──────────────────────────────────────

  Widget _buildTitle(BuildContext context, String businessName) {
    return Column(
      children: [
        // Chip "Listo para vender" — mismos estilos que el resto del wizard
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.emerald.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.emerald.withValues(alpha: 0.3),
            ),
          ),
          child: const Text(
            '✦ Listo para vender',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.emerald,
              letterSpacing: 0.3,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          '¡$businessName\nestá lista!',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                height: 1.2,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'Todo configurado. Vamos a conocer\ntu nuevo panel de control.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.onSurfaceMuted,
                height: 1.5,
              ),
        ),
      ],
    );
  }

  // ─────────────────────────── Summary card ────────────────────────────────

  Widget _buildSummaryCard(OnboardingData data) {
    final businessName = data.businessName.isEmpty ? '—' : data.businessName;
    final warehouse =
        data.warehouseName.isEmpty ? 'Almacén Principal' : data.warehouseName;
    final header = data.ticketHeader.isEmpty ? '—' : data.ticketHeader;

    final planLabel = switch (data.selectedPlan) {
      PlanOption.emprendedor => 'Plan Emprendedor (Prueba 14 días activa)',
      PlanOption.comercio => 'Plan Comercio (Prueba 14 días activa)',
      PlanOption.corporativo => 'Plan Corporativo (Prueba 14 días activa)',
      PlanOption.skipped => 'Sin plan seleccionado',
    };
    final planColor = data.selectedPlan == PlanOption.skipped
        ? AppColors.onSurfaceMuted
        : AppColors.emerald;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          _summaryRow(
            icon: Icons.storefront_rounded,
            label: 'COMERCIO',
            value: businessName,
            valueColor: AppColors.onSurface,
            trailingLabel: '● Activo',
            trailingColor: AppColors.emerald,
          ),
          _divider(),
          _summaryRow(
            icon: Icons.warehouse_rounded,
            label: 'ALMACÉN INICIAL',
            value: warehouse,
            valueColor: AppColors.onSurface,
          ),
          _divider(),
          _summaryRow(
            icon: Icons.receipt_long_rounded,
            label: 'ENCABEZADO DE RECIBO',
            value: header,
            valueColor: AppColors.onSurface,
          ),
          _divider(),
          _summaryRow(
            icon: Icons.workspace_premium_rounded,
            label: 'ESTADO DE CUENTA',
            value: planLabel,
            valueColor: planColor,
          ),
        ],
      ),
    );
  }

  Widget _summaryRow({
    required IconData icon,
    required String label,
    required String value,
    required Color valueColor,
    String? trailingLabel,
    Color? trailingColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.onSurfaceMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurfaceMuted,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: valueColor,
                  ),
                ),
              ],
            ),
          ),
          if (trailingLabel != null)
            Text(
              trailingLabel,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: trailingColor ?? AppColors.onSurfaceMuted,
              ),
            ),
        ],
      ),
    );
  }

  Widget _divider() => const Divider(
        height: 1,
        indent: 16,
        endIndent: 16,
        color: AppColors.border,
      );

  // ─────────────────────────── Tip card ────────────────────────────────────

  Widget _buildTipCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.emerald.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.emerald.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.tips_and_updates_rounded,
            size: 18,
            color: AppColors.emerald,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tip de inicio rápido',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.emerald,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tu caja ya está abierta para registrar tu primera venta, '
                  'o añade tus productos desde el menú de inventario.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.onSurfaceMuted,
                        height: 1.4,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────── CTA ─────────────────────────────────────────

  Widget _buildCta(bool isSaving) {
    return ElevatedButton(
      onPressed: isSaving ? null : _navigateToDashboard,
      child: isSaving
          ? const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.darkSlate,
              ),
            )
          : const Text('Comenzar  →'),
    );
  }
}
