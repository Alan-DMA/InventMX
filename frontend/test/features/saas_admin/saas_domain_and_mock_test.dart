import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/features/saas_admin/data/saas_repository.dart';
import 'package:nexus_app/features/saas_admin/domain/founder_metrics.dart';
import 'package:nexus_app/features/saas_admin/domain/subscription.dart';

/// Tarea 14.2 — dominio (parsers contra el JSON real del backend) y reglas
/// del `SaasRepositoryMock` (mismas que `backend/app/api/v1/saas.py`).
void main() {
  group('Dominio — parsers tolerantes y formato', () {
    test('Subscription.fromJson lee la forma real de GET /subscription', () {
      final sub = Subscription.fromJson(const {
        'tenant': {'id': 't1', 'code': '150467', 'name': 'Bodega El Sol', 'plan_id': 'p2', 'subscription_status': 'SOFT_LOCK'},
        'plan': {'id': 'p2', 'name': 'Comercio', 'price': '399.00', 'max_users': 5, 'max_warehouses': 3},
        'status': 'SOFT_LOCK',
        'pending_invoice': {'id': 'i1', 'tenant_id': 't1', 'plan_id': 'p2', 'plan_name': 'Comercio', 'amount': '399.00', 'due_date': '2026-09-30T00:00:00', 'status': 'PENDIENTE'},
        'pending_validation': {'id': 'v1', 'subscription_invoice_id': 'i1', 'payment_method': 'SPEI', 'reference_number': 'RAST1', 'status': 'PENDIENTE'},
        'days_overdue': 3,
        'soft_lock_at': '2026-10-01T00:00:00',
        'hard_lock_at': '2026-10-11T00:00:00',
        'payment_instructions': {'clabe': '646180157000000004', 'bank': 'STP', 'holder': 'Nexus', 'concept': '150467', 'amount': '399.00'},
        'oxxo': null,
      });
      expect(sub.status, SubscriptionStatus.softLock);
      expect(sub.plan!.priceMxn, 399);
      expect(sub.pendingInvoice!.status, InvoiceStatus.pendiente);
      expect(sub.hasPaymentInReview, isTrue);
      expect(sub.daysOverdue, 3);
      expect(sub.spei!.concept, '150467');
      expect(sub.spei!.clabeGrouped, '6461 8015 7000 0000 04');
      expect(sub.oxxo, isNull);
    });

    test('estados en español e inglés se entienden igual', () {
      expect(InvoiceStatus.fromApi('PAGADA'), InvoiceStatus.pagada);
      expect(InvoiceStatus.fromApi('PAID'), InvoiceStatus.pagada);
      expect(ValidationStatus.fromApi('RECHAZADA'), ValidationStatus.rechazada);
      expect(ValidationStatus.fromApi('REJECTED'), ValidationStatus.rechazada);
      expect(SubscriptionStatus.fromApi('HARD_LOCK'), SubscriptionStatus.hardLock);
      expect(SubscriptionStatus.fromApi(null), SubscriptionStatus.active);
      expect(SaasPaymentMethod.fromApi('OXXO_PAY'), SaasPaymentMethod.oxxo);
    });

    test('mxn y fechas cortas', () {
      expect(mxn(399), '\$399.00');
      expect(mxn(12345.5), '\$12,345.50');
      expect(shortDate(DateTime(2026, 9, 30)), '30 sep');
      expect(periodLabel(DateTime(2026, 9, 30)), 'Sep 2026');
    });

    test('SaasProfile.fromJson lee GET /me', () {
      final p = SaasProfile.fromJson(const {
        'user': {'id': 'u', 'email': 'a@nexus.mx', 'username': 'a', 'role_name': 'TENANT_OWNER'},
        'permissions': ['saas.manage'],
        'is_founder': true,
        'tenant': {'id': 't', 'code': 'NEXUS0', 'name': 'Nexus HQ', 'subscription_status': 'ACTIVE'},
      });
      expect(p.isFounder, isTrue);
      expect(p.isOwner, isTrue);
      expect(p.permissions, ['saas.manage']);
    });
  });

  group('SaasRepositoryMock — reglas de negocio', () {
    final now = DateTime(2026, 9, 14);
    SaasRepositoryMock founder({String tenant = 't-sol'}) => SaasRepositoryMock(
          currentEmail: 'eduardo@nexus.mx',
          currentTenantId: tenant,
          latency: Duration.zero,
          now: () => now,
        );

    test('comercio activo: factura pendiente, SPEI con concepto = código, OXXO en mock', () async {
      final sub = await founder().getSubscription();
      expect(sub.status, SubscriptionStatus.active);
      expect(sub.pendingInvoice!.amountMxn, 399);
      expect(sub.spei!.concept, '150467');
      expect(sub.spei!.amountMxn, 399);
      expect(sub.oxxo, isNotNull);
      expect(sub.daysUntilDue(now), 16);
    });

    test('cambiar plan recalcula la factura pendiente', () async {
      final repo = founder();
      final sub = await repo.changePlan('plan-emprendedor');
      expect(sub.plan!.name, 'Emprendedor');
      expect(sub.pendingInvoice!.amountMxn, 199);
    });

    test('"Ya pagué" deja el aviso en revisión, no se duplica y bloquea cambio de plan', () async {
      final repo = founder();
      final sub = await repo.getSubscription();
      final v = await repo.reportPayment(
        invoiceId: sub.pendingInvoice!.id,
        method: SaasPaymentMethod.spei,
        reference: 'RAST123',
      );
      expect(v.status, ValidationStatus.pendiente);
      expect((await repo.getSubscription()).hasPaymentInReview, isTrue);
      expect(
        () => repo.reportPayment(invoiceId: sub.pendingInvoice!.id, method: SaasPaymentMethod.spei, reference: 'OTRA1'),
        throwsA(isA<SaasException>()),
      );
      expect(() => repo.changePlan('plan-corporativo'), throwsA(isA<SaasException>()));
    });

    test('no fundador no entra al panel', () async {
      final repo = SaasRepositoryMock(currentEmail: 'sol@tiendita.mx', latency: Duration.zero, now: () => now);
      expect(() => repo.getFounderMetrics(), throwsA(isA<SaasException>()));
    });

    test('MRR = suma de planes de los ACTIVE; conteos por estado', () async {
      final m = await founder().getFounderMetrics();
      // sol 399 + pepe 199 + norte 699 + mary 399 + tres 199 = 1895
      expect(m.mrrMxn, 1895);
      expect(m.tenantsActive, 5);
      expect(m.tenantsSoftLock, 2);
      expect(m.tenantsHardLock, 1);
      expect(m.tenantsTotal, 8);
      expect(m.pendingValidations, 2);
    });

    test('aprobar: factura pagada, comercio ACTIVE, siguiente periodo, MRR sube', () async {
      final repo = founder(tenant: 't-esquina');
      final before = await repo.getSubscription();
      expect(before.status, SubscriptionStatus.hardLock);
      final inbox = await repo.getValidationInbox();
      final item = inbox.firstWhere((i) => i.tenantId == 't-esquina');

      await repo.approveValidation(item.validation.id, notes: 'Visto en banco');

      final after = await repo.getSubscription();
      expect(after.status, SubscriptionStatus.active);
      expect(after.pendingInvoice!.id, isNot(before.pendingInvoice!.id));
      expect(after.pendingInvoice!.dueDate, addMonths(before.pendingInvoice!.dueDate, 1));
      expect(after.hasPaymentInReview, isFalse);
      final m = await repo.getFounderMetrics();
      expect(m.mrrMxn, 1895 + 399);
      expect((await repo.getValidationInbox()).length, 1);
      expect(() => repo.approveValidation(item.validation.id), throwsA(isA<SaasException>()));
    });

    test('rechazar exige motivo y deja la factura pendiente con el motivo visible', () async {
      final repo = founder(tenant: 't-lupita');
      final item = (await repo.getValidationInbox()).firstWhere((i) => i.tenantId == 't-lupita');
      expect(() => repo.rejectValidation(item.validation.id, notes: ''), throwsA(isA<SaasException>()));
      await repo.rejectValidation(item.validation.id, notes: 'No aparece en el banco');
      final sub = await repo.getSubscription();
      expect(sub.status, SubscriptionStatus.softLock);
      expect(sub.pendingValidation!.status, ValidationStatus.rechazada);
      expect(sub.pendingValidation!.notes, 'No aparece en el banco');
      expect(sub.hasPaymentInReview, isFalse);
    });

    test('filtros de comercios por estado y búsqueda', () async {
      final repo = founder();
      final soft = await repo.getTenants(const TenantFilter(status: SubscriptionStatus.softLock));
      expect(soft.map((t) => t.id), containsAll(['t-lupita', 't-centro']));
      expect(soft.length, 2);
      final byCode = await repo.getTenants(const TenantFilter(query: '5098'));
      expect(byCode.single.name, 'La Esquina');
      final byName = await repo.getTenants(const TenantFilter(query: 'cremería'));
      expect(byName.single.code, '611004');
    });

    test('reactivar corre el vencimiento 7 días; extender plazo reactiva', () async {
      final repo = founder(tenant: 't-esquina');
      final t = await repo.setTenantStatus('t-esquina', SubscriptionStatus.active);
      expect(t.status, SubscriptionStatus.active);
      expect(t.daysOverdue, 0);
      expect(t.pendingInvoice!.dueDate, now.add(const Duration(days: 7)));

      final centro = await repo.extendDueDate('t-centro', 10);
      expect(centro.dueDate, now.add(const Duration(days: 10)));
      final list = await repo.getTenants(const TenantFilter(query: 'Centro'));
      expect(list.single.status, SubscriptionStatus.active);

      final susp = await repo.setTenantStatus('t-sol', SubscriptionStatus.hardLock);
      expect(susp.status, SubscriptionStatus.hardLock);
      expect((await repo.getSubscription()).status, SubscriptionStatus.active); // esquina, no sol
    });
  });
}
