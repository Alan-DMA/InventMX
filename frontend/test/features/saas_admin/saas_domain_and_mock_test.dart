import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nexus_app/core/network/dio_client.dart';
import 'package:nexus_app/features/saas_admin/data/saas_repository.dart';
import 'package:nexus_app/features/saas_admin/domain/subscription.dart';

class MockDioClient extends Mock implements DioClient {}

/// Suscripción prepago (P9–P13): parsers contra el JSON real de
/// `GET /api/v1/subscription` y `/subscription/activity`, reglas del mock y
/// la implementación real con Dio simulado.
void main() {
  group('Dominio', () {
    test('Subscription.fromJson lee la forma real de GET /subscription', () {
      final sub = Subscription.fromJson(const {
        'id': 't1',
        'tenant_name': 'Abarrotes Sol',
        'slug': 'abarrotes-sol',
        'plan': 'COMERCIO',
        'status': 'ACTIVE',
        'current_period_start': '2026-08-28T17:00:00Z',
        'current_period_end': '2026-09-28T17:00:00Z',
        'monthly_fee_mxn': '399.00',
        'usage_stats': {
          'products_count': 40,
          'products_limit': 999999,
          'monthly_sales_mxn': '0.00',
          'monthly_sales_limit_mxn': null,
          'users_count': 3,
          'users_limit': 5,
        },
        'paid_until': '2026-09-28T17:00:00Z',
        'grace_until': '2026-10-08T17:00:00Z',
        'entitlement': 'GRACIA',
        'subscription_source': 'TRIAL',
        'renewal_channel': 'NONE',
      });
      expect(sub.plan, SaasPlanId.comercio);
      expect(sub.monthlyFeeMxn, 399);
      expect(sub.entitlement, Entitlement.gracia);
      expect(sub.renewalChannel, RenewalChannel.none);
      expect(sub.canRenewInApp, isFalse);
      expect(sub.usersCount, 3);
      expect(sub.usersLimit, 5);
      expect(sub.paidUntil!.toUtc(), DateTime.utc(2026, 9, 28, 17));
      expect(sub.daysOfGraceLeft(DateTime(2026, 10, 1)), 7);
    });

    test('valores desconocidos caen en lo seguro', () {
      expect(Entitlement.fromApi(null), Entitlement.sinFecha);
      expect(RenewalChannel.fromApi('GOOGLE_PLAY'), RenewalChannel.googlePlay);
      expect(RenewalChannel.fromApi('OTRO'), RenewalChannel.none);
      expect(SaasPlanId.fromApi('CORPORATIVO'), SaasPlanId.corporativo);
      expect(SubscriptionStatus.fromApi('HARD_LOCK'), SubscriptionStatus.hardLock);
      expect(SubscriptionStatus.fromApi(null), SubscriptionStatus.active);
    });

    test('SupportActivity.fromJson lee la actividad de soporte', () {
      final a = SupportActivity.fromJson(const {
        'occurred_at': '2026-09-27T18:00:00Z',
        'action': 'PAYMENT_CONFIRMED',
        'summary': 'Confirmamos tu pago de \$199.00 en efectivo.',
        'reason': 'Pagó en efectivo en la visita.',
        'by': 'Soporte Nexus · Eduardo',
      });
      expect(a.summary, contains('199.00'));
      expect(a.reason, 'Pagó en efectivo en la visita.');
      expect(a.by, 'Soporte Nexus · Eduardo');
    });

    test('mxn, fechas y meses', () {
      expect(mxn(399), '\$399.00');
      expect(mxn(12345.5), '\$12,345.50');
      expect(mxn(-279.5), '−\$279.50');
      expect(shortDate(DateTime(2026, 9, 30)), '30 sep');
      expect(longDate(DateTime(2026, 9, 30)), '30 sep 2026');
      expect(periodLabel(DateTime(2026, 9, 30)), 'Sep 2026');
      expect(addMonths(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
    });
  });

  group('Mock', () {
    final now = DateTime(2026, 9, 14);

    test('vigente, en gracia y vencida según los días al vencimiento', () async {
      final vigente = await SaasRepositoryMock(latency: Duration.zero, now: () => now).getSubscription();
      expect(vigente.entitlement, Entitlement.vigente);
      expect(vigente.status, SubscriptionStatus.active);

      final gracia = await SaasRepositoryMock(latency: Duration.zero, now: () => now, daysUntilDue: -4)
          .getSubscription();
      expect(gracia.entitlement, Entitlement.gracia);
      expect(gracia.status, SubscriptionStatus.active, reason: 'P10: en gracia, acceso completo');

      final vencida = await SaasRepositoryMock(latency: Duration.zero, now: () => now, daysUntilDue: -15)
          .getSubscription();
      expect(vencida.entitlement, Entitlement.vencida);
      expect(vencida.status, SubscriptionStatus.hardLock);
    });
  });

  group('Implementación real', () {
    late MockDioClient client;
    late SaasRepositoryImpl repo;

    setUp(() {
      client = MockDioClient();
      repo = SaasRepositoryImpl(client: client);
    });

    void stubGet(String path, dynamic data) {
      when(() => client.get<dynamic>(path,
              queryParameters: any(named: 'queryParameters'), options: any(named: 'options')))
          .thenAnswer((_) async => Response(
              data: data, statusCode: 200, requestOptions: RequestOptions(path: path)));
    }

    test('lee /subscription y /subscription/activity', () async {
      stubGet('/api/v1/subscription', {
        'id': 't1',
        'tenant_name': 'Abarrotes Sol',
        'plan': 'EMPRENDEDOR',
        'status': 'ACTIVE',
        'monthly_fee_mxn': '199.00',
        'entitlement': 'VIGENTE',
        'renewal_channel': 'NONE',
      });
      stubGet('/api/v1/subscription/activity', [
        {'occurred_at': '2026-09-27T18:00:00Z', 'action': 'COURTESY_GRANTED', 'summary': 'Te dimos un mes.', 'by': 'Soporte Nexus · Alan'},
      ]);

      final sub = await repo.getSubscription();
      expect(sub.tenantName, 'Abarrotes Sol');
      expect(sub.plan, SaasPlanId.emprendedor);
      final activity = await repo.getSupportActivity();
      expect(activity.single.by, 'Soporte Nexus · Alan');
    });

    test('sin red lo dice así', () async {
      when(() => client.get<dynamic>('/api/v1/subscription',
              queryParameters: any(named: 'queryParameters'), options: any(named: 'options')))
          .thenThrow(DioException(
              requestOptions: RequestOptions(path: '/api/v1/subscription'),
              type: DioExceptionType.connectionError));
      await expectLater(
        repo.getSubscription(),
        throwsA(predicate((e) => e is SaasException && e.message.contains('Sin conexión'))),
      );
    });
  });
}
