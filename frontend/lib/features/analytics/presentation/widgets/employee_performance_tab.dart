import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/employee_performance.dart';

/// Tablero de rendimiento del vendedor — Tarea 8.2.3 (`EmployeePerformanceTab`).
///
/// Disposición inspirada en la referencia de Figma (node 68:115), adaptada a
/// la identidad visual oscura de Nexus (Constitución Art. I, 1.2.5): la
/// paleta, tipografía y componentes son los de `AppColors`/`AppTheme`, no los
/// colores claros del diseño original.
///
/// Trazabilidad: Doc. Maestro RF-10 (Sección 5.2), Sección 6 (SR-05)
///              Constitución Art. VII (7.2) · HU-14 / CU-16
class EmployeePerformanceTab extends StatelessWidget {
  const EmployeePerformanceTab({
    super.key,
    required this.performance,
    required this.onPeriodTap,
  });

  final EmployeePerformance performance;
  final VoidCallback onPeriodTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SellerHeader(performance: performance, onPeriodTap: onPeriodTap),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _KpiGrid(performance: performance),
              const SizedBox(height: 16),
              _TasaCard(ratePercent: performance.commissionRatePercent),
              const SizedBox(height: 24),
              const _SectionHeading('Desglose Diario'),
              const SizedBox(height: 12),
              _DailyBreakdownCard(entries: performance.dailyBreakdown),
              const SizedBox(height: 24),
              const _SectionHeading('Ranking del Período'),
              const SizedBox(height: 12),
              _RankingCard(ranking: performance.ranking),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 1. Encabezado del vendedor
// ---------------------------------------------------------------------------

class _SellerHeader extends StatelessWidget {
  const _SellerHeader({required this.performance, required this.onPeriodTap});

  final EmployeePerformance performance;
  final VoidCallback onPeriodTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.skyBlue,
                child: Text(
                  _initialsOf(performance.cashierName),
                  style: const TextStyle(
                    color: AppColors.darkSlate,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      performance.cashierName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      performance.role,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.onSurfaceMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onPeriodTap,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'PERÍODO',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.onSurfaceMuted,
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            performance.periodLabel,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppColors.onSurfaceMuted,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _initialsOf(String name) {
    final base = name.contains('@') ? name.split('@').first : name;
    final parts = base.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final letters = parts.take(2).map((p) => p[0].toUpperCase()).join();
    return letters.isEmpty ? '?' : letters;
  }
}

// ---------------------------------------------------------------------------
// 3. KPI Grid
// ---------------------------------------------------------------------------

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.performance});

  final EmployeePerformance performance;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _KpiCard(
            icon: Icons.account_balance_wallet_rounded,
            label: 'Comisión\nacumulada',
            value: '\$${performance.accumulatedCommissionMxn.toStringAsFixed(2)}',
            valueColor: AppColors.skyBlue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _KpiCard(
            icon: Icons.shopping_cart_rounded,
            label: 'Ventas del período',
            value: '\$${performance.totalSalesMxn.toStringAsFixed(2)}',
            valueColor: AppColors.onSurface,
          ),
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 120),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 16, color: AppColors.onSurfaceMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.onSurfaceMuted,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: valueColor,
              letterSpacing: -0.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 4. Tasa de comisión
// ---------------------------------------------------------------------------

class _TasaCard extends StatelessWidget {
  const _TasaCard({required this.ratePercent});

  final double ratePercent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 20, color: AppColors.onSurfaceMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Tasa comisión: ${ratePercent.toStringAsFixed(0)}% sobre volumen',
              style: const TextStyle(fontSize: 14, color: AppColors.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Encabezados de sección
// ---------------------------------------------------------------------------

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.onSurface,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 5. Desglose diario
// ---------------------------------------------------------------------------

class _DailyBreakdownCard extends StatelessWidget {
  const _DailyBreakdownCard({required this.entries});

  final List<DailyCommissionEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const _EmptyListCard(message: 'Aún no hay ventas registradas hoy.');
    }

    final mono = GoogleFonts.jetBrainsMono();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                border: i < entries.length - 1
                    ? const Border(bottom: BorderSide(color: AppColors.border))
                    : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        _formatDate(entries[i].date),
                        style: mono.copyWith(
                            fontSize: 14, color: AppColors.onSurfaceMuted),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        '${entries[i].salesCount} ventas',
                        style: const TextStyle(
                            fontSize: 14, color: AppColors.onSurface),
                      ),
                    ],
                  ),
                  Text(
                    '+\$${entries[i].commissionMxn.toStringAsFixed(2)}',
                    style: mono.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.emerald,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------------------
// 6. Ranking del período
// ---------------------------------------------------------------------------

class _RankingCard extends StatelessWidget {
  const _RankingCard({required this.ranking});

  final List<RankingEntry> ranking;

  static const _medals = ['🥇', '🥈', '🥉'];

  @override
  Widget build(BuildContext context) {
    if (ranking.isEmpty) {
      return const _EmptyListCard(message: 'Sin datos de ranking todavía.');
    }

    final mono = GoogleFonts.jetBrainsMono();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < ranking.length; i++)
            Container(
              padding: EdgeInsets.only(
                left: ranking[i].isCurrentUser ? 12 : 16,
                right: 16,
                top: 16,
                bottom: 16,
              ),
              decoration: BoxDecoration(
                color: ranking[i].isCurrentUser
                    ? AppColors.skyBlue.withValues(alpha: 0.08)
                    : null,
                border: Border(
                  bottom: i < ranking.length - 1
                      ? const BorderSide(color: AppColors.border)
                      : BorderSide.none,
                  left: ranking[i].isCurrentUser
                      ? const BorderSide(color: AppColors.skyBlue, width: 4)
                      : BorderSide.none,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Text(
                          i < _medals.length ? _medals[i] : '${i + 1}.',
                          style: const TextStyle(fontSize: 18),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            ranking[i].cashierName,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: ranking[i].isCurrentUser
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: ranking[i].isCurrentUser
                                  ? AppColors.skyBlue
                                  : AppColors.onSurface,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (ranking[i].isCurrentUser) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.skyBlue.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              '(yo)',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.skyBlue,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Text(
                    '\$${ranking[i].commissionMxn.toStringAsFixed(2)}',
                    style: mono.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: ranking[i].isCurrentUser
                          ? AppColors.skyBlue
                          : AppColors.onSurface,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Estado vacío compartido por las listas
// ---------------------------------------------------------------------------

class _EmptyListCard extends StatelessWidget {
  const _EmptyListCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted),
      ),
    );
  }
}
