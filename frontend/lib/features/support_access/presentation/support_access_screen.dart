import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/data/auth_repository.dart';
import '../../saas_admin/domain/subscription.dart' show longDate;
import '../../support/domain/support_models.dart' show caseMoment, clockTime;
import '../data/support_access_repository.dart';
import 'support_visits_provider.dart';

/// La entrada del menú: oculta hasta la etapa 4 (P26); con la sesión de
/// sólo lectura de soporte, conceder ya tiene efecto y se ofrece.
const bool kSupportAccessVisible = bool.fromEnvironment('SUPPORT_ACCESS', defaultValue: true);

final supportAccessRepositoryProvider = Provider<SupportAccessRepository>(
  (ref) => SupportAccessRepositoryImpl(client: ref.watch(dioClientProvider)),
);

final supportAccessStatusProvider = FutureProvider.autoDispose<SupportAccessStatus>(
  (ref) => ref.watch(supportAccessRepositoryProvider).status(),
);

/// "Hoy" inyectable para la cuenta regresiva en tests.
final supportAccessClockProvider = Provider<DateTime Function()>((_) => DateTime.now);

/// Acceso de soporte (dueño): quién puede ver la tienda, por cuánto tiempo, y
/// quitarlo en un toque. El estado va primero, en palabras; lo que soporte
/// puede y no puede hacer, antes del botón. 1 hora preseleccionada: el default
/// que más protege (principio de defaults éticos).
class SupportAccessScreen extends ConsumerStatefulWidget {
  const SupportAccessScreen({super.key});

  static const durations = <(int, String)>[(1, '1 hora'), (24, '24 horas'), (72, '3 días')];

  @override
  ConsumerState<SupportAccessScreen> createState() => _SupportAccessScreenState();
}

class _SupportAccessScreenState extends ConsumerState<SupportAccessScreen> {
  int _hours = 1;
  bool _busy = false;
  String? _error;
  SupportAccessStatus? _latest;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // La cuenta regresiva se refresca cada minuto
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    // Abrir esta pantalla da por vistas las entradas de soporte (aviso y número del ☰)
    Future.microtask(() => ref.read(supportVisitsSeenProvider.notifier).markSeen(ref.read(supportAccessClockProvider)()));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _run(Future<SupportAccessStatus> Function(SupportAccessRepository) action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final status = await action(ref.read(supportAccessRepositoryProvider));
      if (mounted) setState(() => _latest = status);
      // El aviso y el número del ☰ siguen a lo que acaba de pasar (p. ej. quitar el acceso)
      ref.invalidate(supportVisitsProvider);
    } on SupportAccessException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _remaining(DateTime until, DateTime now) {
    final left = until.difference(now);
    // Hasta hora y media se cuenta en minutos: "1 h" diría poco en la última hora
    if (left.inMinutes < 90) return 'quedan ${left.inMinutes.clamp(1, 89)} min';
    if (left.inHours < 48) return 'quedan ${left.inHours} h';
    return 'quedan ${left.inDays} días';
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(supportAccessStatusProvider);
    final status = _latest ?? async.valueOrNull;
    final now = ref.watch(supportAccessClockProvider)();

    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      appBar: AppBar(backgroundColor: AppColors.darkSlate, elevation: 0, title: const Text('Acceso de soporte')),
      body: status == null
          ? Center(
              child: async.hasError
                  ? TextButton(
                      onPressed: () => ref.invalidate(supportAccessStatusProvider),
                      child: const Text('No pudimos cargarlo. Reintentar'),
                    )
                  : const CircularProgressIndicator(color: AppColors.emerald),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Text(
                  status.active == null
                      ? 'Soporte Nexus no puede ver tu tienda.'
                      : 'Soporte Nexus puede ver tu tienda hasta el ${longDate(status.active!.expiresAt)} a las '
                          '${clockTime(status.active!.expiresAt)} '
                          '(${_remaining(status.active!.expiresAt, now)}).',
                  key: const Key('supportAccessState'),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.onSurface, height: 1.25),
                ),
                const SizedBox(height: 18),
                const _Rule(icon: Icons.visibility_outlined, text: 'Puede ver productos, ventas, caja y reportes para encontrar un problema.'),
                const _Rule(icon: Icons.block_rounded, text: 'No puede vender, cambiar precios ni borrar nada, y nunca ve contraseñas.'),
                const _Rule(icon: Icons.history_rounded, text: 'Cada vez que entra queda registrado y lo ves aquí.'),
                const SizedBox(height: 20),
                // Si soporte está dentro, se dice junto al botón que lo saca
                for (final visit in status.visitsNow) ...[
                  _VisitNow(visit: visit),
                  const SizedBox(height: 14),
                ],
                if (status.active == null) ...[
                  const Text('¿Por cuánto tiempo?',
                      style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
                  const SizedBox(height: 10),
                  SegmentedButton<int>(
                    key: const Key('supportAccessDuration'),
                    segments: [
                      for (final (hours, label) in SupportAccessScreen.durations)
                        ButtonSegment(value: hours, label: Text(label)),
                    ],
                    selected: {_hours},
                    showSelectedIcon: false,
                    onSelectionChanged: _busy ? null : (s) => setState(() => _hours = s.first),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      key: const Key('supportAccessGrant'),
                      onPressed: _busy ? null : () => _run((r) => r.grant(_hours)),
                      child: Text('Permitir acceso por ${SupportAccessScreen.durations.firstWhere((d) => d.$1 == _hours).$2}'),
                    ),
                  ),
                ] else
                  SizedBox(
                    height: 52,
                    child: OutlinedButton(
                      key: const Key('supportAccessRevoke'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.onSurface,
                        side: const BorderSide(color: AppColors.border),
                        // El corte de un toque va en la misma letra que la pantalla que lo rodea
                        textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      onPressed: _busy ? null : () => _run((r) => r.revoke()),
                      child: const Text('Quitar acceso ahora'),
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13.5)),
                  ),
                // Las que ya terminaron (la que sigue abierta va en su tarjeta, arriba)
                if (status.visits.any((v) => !v.active)) ...[
                  const SizedBox(height: 28),
                  Semantics(
                    header: true,
                    child: const Text('Quién entró',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
                  ),
                  const SizedBox(height: 4),
                  for (final (i, v) in status.visits.where((v) => !v.active).indexed) ...[
                    if (i > 0) const Divider(color: AppColors.border, height: 1),
                    _VisitRow(visit: v),
                  ],
                ],
                if (status.history.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  const Text('Permisos que diste',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
                  const SizedBox(height: 8),
                  for (final g in status.history)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Concediste ${_duration(g)} el ${caseMoment(g.createdAt)}'
                        '${g.revokedAt != null ? ' · lo quitaste el ${caseMoment(g.revokedAt!)}' : g.active ? ' · vigente' : ' · venció'}',
                        style: const TextStyle(fontSize: 13.5, color: AppColors.onSurfaceMuted, height: 1.4),
                      ),
                    ),
                ],
              ],
            ),
    );
  }

  static String _duration(AccessGrant g) {
    final hours = g.expiresAt.difference(g.createdAt).inHours;
    return hours >= 48 ? '${(hours / 24).round()} días' : (hours == 1 ? '1 hora' : '$hours horas');
  }
}

class _Rule extends StatelessWidget {
  const _Rule({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: AppColors.onSurfaceMuted),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 14.5, color: AppColors.onSurface, height: 1.4))),
          ],
        ),
      );
}


/// Soporte está dentro ahora mismo: quién, desde cuándo y por qué. Quitar el
/// acceso (el botón de abajo) lo saca en su siguiente movimiento.
class _VisitNow extends StatelessWidget {
  const _VisitNow({required this.visit});
  final SupportVisit visit;

  @override
  Widget build(BuildContext context) => Container(
        key: Key('supportVisitNow_${visit.id}'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.skyBlue.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.visibility_outlined, size: 20, color: AppColors.skyBlue),
                SizedBox(width: 10),
                Expanded(
                  child: Text('Soporte está viendo tu tienda ahora',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${visit.by} · sólo lectura${visit.openedAt != null ? ' · entró a las ${clockTime(visit.openedAt!)}' : ''}',
              style: const TextStyle(fontSize: 13.5, color: AppColors.onSurfaceMuted, height: 1.4),
            ),
            const SizedBox(height: 6),
            Text('Motivo: ${visit.reason}',
                style: const TextStyle(fontSize: 14.5, color: AppColors.onSurface, height: 1.4)),
            if (visit.sections.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Ha revisado: ${visit.sections.join(', ')}',
                  style: const TextStyle(fontSize: 13.5, color: AppColors.onSurfaceMuted, height: 1.4)),
            ],
          ],
        ),
      );
}

/// Una entrada de soporte en "Quién entró".
class _VisitRow extends StatelessWidget {
  const _VisitRow({required this.visit});
  final SupportVisit visit;

  @override
  Widget build(BuildContext context) {
    final when = visit.openedAt != null ? caseMoment(visit.openedAt!) : '';
    final minutes = visit.minutes;
    final duration = minutes == null ? '' : ' · ${visit.active ? 'lleva' : 'estuvo'} $minutes\u00A0min';
    return Padding(
      key: Key('supportVisit_${visit.id}'),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(visit.by, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
          const SizedBox(height: 2),
          Text('$when$duration${visit.active ? ' · ahora' : ''}',
              style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted,
                  fontFeatures: [FontFeature.tabularFigures()])),
          const SizedBox(height: 6),
          Text('Motivo: ${visit.reason}', style: const TextStyle(fontSize: 14, color: AppColors.onSurface, height: 1.4)),
          if (visit.sections.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Revisó: ${visit.sections.join(', ')}',
                style: const TextStyle(fontSize: 13.5, color: AppColors.onSurfaceMuted, height: 1.4)),
          ],
          if (!visit.active && visit.endText != null) ...[
            const SizedBox(height: 4),
            Text(visit.endText!, style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted)),
          ],
        ],
      ),
    );
  }
}
