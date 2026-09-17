import 'package:dio/dio.dart';
import '../../../core/network/dio_client.dart';
import '../domain/founder_metrics.dart';
import '../domain/subscription.dart';

/// Contrato del módulo SaaS — Tarea 14.2.
///
/// Rutas reales del backend (`backend/app/api/v1/saas.py`, prefijo
/// `/api/v1/saas`). Dos caras: la del **comerciante** (autenticado, aunque
/// esté bloqueado por morosidad) y la de los **fundadores** (`saas.manage`).
abstract class SaasRepository {
  // --- Comerciante ---

  /// `GET /me` — permisos, si es fundador y estado del comercio.
  Future<SaasProfile> getProfile();

  /// `GET /plans`.
  Future<List<SaasPlan>> getPlans();

  /// `GET /subscription` — plan, estado, factura pendiente, instrucciones.
  Future<Subscription> getSubscription();

  /// `GET /invoices` — historial, más reciente primero.
  Future<List<SubscriptionInvoice>> getInvoices();

  /// `POST /subscription/change-plan`.
  Future<Subscription> changePlan(String planId);

  /// `POST /payment-validations` — "Ya pagué".
  Future<PaymentValidation> reportPayment({
    required String invoiceId,
    required SaasPaymentMethod method,
    required String reference,
  });

  /// `GET /payment-validations` — los avisos propios, más reciente primero.
  Future<List<PaymentValidation>> getMyValidations();

  // --- Fundadores ---

  /// `GET /admin/metrics`.
  Future<FounderMetrics> getFounderMetrics();

  /// `GET /admin/tenants?status&plan_id&q`.
  Future<List<TenantSummary>> getTenants(TenantFilter filter);

  /// `GET /admin/payment-validations?status=PENDIENTE`.
  Future<List<ValidationInboxItem>> getValidationInbox();

  /// `POST /admin/payment-validations/{id}/approve`.
  Future<void> approveValidation(String validationId, {String? notes});

  /// `POST /admin/payment-validations/{id}/reject` — motivo obligatorio.
  Future<void> rejectValidation(String validationId, {required String notes});

  /// `POST /admin/tenants/{id}/status` — reactivar o suspender.
  Future<TenantSummary> setTenantStatus(
      String tenantId, SubscriptionStatus status);

  /// `POST /admin/tenants/{id}/extend-due`.
  Future<SubscriptionInvoice> extendDueDate(String tenantId, int days);
}

/// Fallo con mensaje para pantalla. `code` conserva el del backend cuando llega.
class SaasException implements Exception {
  const SaasException(this.message, {this.code, this.statusCode});
  final String message;
  final String? code;
  final int? statusCode;

  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// Implementación real — /api/v1/saas
// ---------------------------------------------------------------------------

class SaasRepositoryImpl implements SaasRepository {
  SaasRepositoryImpl({required this.client});

  final DioClient client;
  static const _base = '/api/v1/saas';

  @override
  Future<SaasProfile> getProfile() async =>
      SaasProfile.fromJson(await _getMap('$_base/me'));

  @override
  Future<List<SaasPlan>> getPlans() async =>
      (await _getList('$_base/plans')).map(SaasPlan.fromJson).toList();

  @override
  Future<Subscription> getSubscription() async =>
      Subscription.fromJson(await _getMap('$_base/subscription'));

  @override
  Future<List<SubscriptionInvoice>> getInvoices() async =>
      (await _getList('$_base/invoices'))
          .map(SubscriptionInvoice.fromJson)
          .toList();

  @override
  Future<Subscription> changePlan(String planId) async => Subscription.fromJson(
        await _postMap('$_base/subscription/change-plan', {'plan_id': planId}),
      );

  @override
  Future<PaymentValidation> reportPayment({
    required String invoiceId,
    required SaasPaymentMethod method,
    required String reference,
  }) async =>
      PaymentValidation.fromJson(await _postMap('$_base/payment-validations', {
        'invoice_id': invoiceId,
        'payment_method': method.apiValue,
        'reference_number': reference,
      }));

  @override
  Future<List<PaymentValidation>> getMyValidations() async =>
      (await _getList('$_base/payment-validations'))
          .map(PaymentValidation.fromJson)
          .toList();

  @override
  Future<FounderMetrics> getFounderMetrics() async =>
      FounderMetrics.fromJson(await _getMap('$_base/admin/metrics'));

  @override
  Future<List<TenantSummary>> getTenants(TenantFilter filter) async {
    final query = <String, dynamic>{
      if (filter.status != null) 'status': filter.status!.apiValue,
      if (filter.planId != null) 'plan_id': filter.planId,
      if (filter.query.trim().isNotEmpty) 'q': filter.query.trim(),
    };
    return (await _getList('$_base/admin/tenants', query: query))
        .map(TenantSummary.fromJson)
        .toList();
  }

  @override
  Future<List<ValidationInboxItem>> getValidationInbox() async =>
      (await _getList('$_base/admin/payment-validations',
              query: {'status': 'PENDIENTE'}))
          .map(ValidationInboxItem.fromJson)
          .toList();

  @override
  Future<void> approveValidation(String validationId, {String? notes}) =>
      _postMap('$_base/admin/payment-validations/$validationId/approve', {
        if (notes != null && notes.isNotEmpty) 'validation_notes': notes,
      });

  @override
  Future<void> rejectValidation(String validationId, {required String notes}) =>
      _postMap('$_base/admin/payment-validations/$validationId/reject', {
        'validation_notes': notes,
      });

  @override
  Future<TenantSummary> setTenantStatus(
    String tenantId,
    SubscriptionStatus status,
  ) async =>
      TenantSummary.fromJson(await _postMap(
        '$_base/admin/tenants/$tenantId/status',
        {'status': status.apiValue},
      ));

  @override
  Future<SubscriptionInvoice> extendDueDate(String tenantId, int days) async =>
      SubscriptionInvoice.fromJson(await _postMap(
        '$_base/admin/tenants/$tenantId/extend-due',
        {'days': days},
      ));

  // --- Helpers HTTP ---

  Future<Map<dynamic, dynamic>> _getMap(String path,
      {Map<String, dynamic>? query}) async {
    try {
      final res = await client.get(path, queryParameters: query);
      final data = res.data;
      if (data is Map) return data;
      throw const SaasException('Respuesta inválida del servidor.');
    } on DioException catch (e) {
      throw mapSaasDioError(e);
    }
  }

  Future<List<Map<dynamic, dynamic>>> _getList(String path,
      {Map<String, dynamic>? query}) async {
    try {
      final res = await client.get(path, queryParameters: query);
      final data = res.data;
      if (data is List) return data.whereType<Map>().toList();
      throw const SaasException('Respuesta inválida del servidor.');
    } on DioException catch (e) {
      throw mapSaasDioError(e);
    }
  }

  Future<Map<dynamic, dynamic>> _postMap(String path, Object body) async {
    try {
      final res = await client.post(path, data: body);
      final data = res.data;
      if (data is Map) return data;
      return const {};
    } on DioException catch (e) {
      throw mapSaasDioError(e);
    }
  }
}

/// Convierte el error HTTP en un mensaje que el tendero puede leer.
/// Respeta `detail.code` (TENANT_SOFT_LOCK / TENANT_HARD_LOCK /
/// SAAS_FOUNDER_ONLY) del backend legacy.
SaasException mapSaasDioError(DioException e) {
  final status = e.response?.statusCode;
  final data = e.response?.data;
  String? message;
  String? code;
  if (data is Map) {
    final detail = data['detail'];
    if (detail is Map) {
      message = detail['message']?.toString();
      code = detail['code']?.toString();
    } else if (detail != null) {
      message = detail.toString();
    } else if (data['error'] is Map) {
      message = (data['error'] as Map)['message']?.toString();
      code = (data['error'] as Map)['code']?.toString();
    }
  }
  if (message == null) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      message = 'Sin conexión con el servidor. Verifica tu red.';
    } else if (status == 401) {
      message = 'Tu sesión expiró. Vuelve a iniciar sesión.';
    } else if (status == 403) {
      message = 'No tienes permiso para esta acción.';
    } else {
      message = 'No se pudo completar la operación. Inténtalo de nuevo.';
    }
  }
  return SaasException(message, code: code, statusCode: status);
}

// ---------------------------------------------------------------------------
// Mock — activo con `--dart-define=SAAS_MOCK=true` y en tests (D9)
// ---------------------------------------------------------------------------

/// Comercios sembrados con la misma regla de negocio que el backend: aprobar
/// un aviso paga la factura y reactiva; la morosidad escala por días vencidos;
/// el MRR es la suma de la tarifa de los ACTIVE. El comercio de la sesión es
/// `currentTenantId`; el fundador se decide por el correo (`@nexus.mx`).
class SaasRepositoryMock implements SaasRepository {
  SaasRepositoryMock({
    this.currentEmail = 'demo@nexus.mx',
    this.currentTenantId = 't-sol',
    this.latency = const Duration(milliseconds: 350),
    this.includeOxxo = true,
    DateTime Function()? now,
    List<TenantSummary>? tenants,
  }) : now = now ?? DateTime.now {
    _tenants = tenants ?? _seedTenants(this.now());
    for (final t in _tenants) {
      if (t.pendingInvoice != null) _invoices.add(t.pendingInvoice!);
    }
    // Avisos de pago en revisión para que la bandeja no nazca vacía.
    _seedValidations();
  }

  final String currentEmail;
  final String currentTenantId;
  final Duration latency;

  /// `false` reproduce al backend real (sin proveedor OXXO → `oxxo: null`).
  final bool includeOxxo;
  final DateTime Function() now;

  static const plans = [
    SaasPlan(
        id: 'plan-emprendedor',
        name: 'Emprendedor',
        priceMxn: 199,
        maxUsers: 2,
        maxWarehouses: 1),
    SaasPlan(
        id: 'plan-comercio',
        name: 'Comercio',
        priceMxn: 399,
        maxUsers: 5,
        maxWarehouses: 3),
    SaasPlan(
        id: 'plan-corporativo',
        name: 'Corporativo',
        priceMxn: 699,
        maxUsers: 15,
        maxWarehouses: 10),
  ];

  static const clabe = '646180157000000004';
  static const bank = 'STP';
  static const holder = 'Nexus';

  late List<TenantSummary> _tenants;
  final List<SubscriptionInvoice> _invoices = [];
  final List<ValidationInboxItem> _validations = [];
  int _seq = 0;

  bool get isFounder => currentEmail.toLowerCase().endsWith('@nexus.mx');

  static List<TenantSummary> _seedTenants(DateTime now) {
    SubscriptionInvoice inv(String id, SaasPlan plan, int dueInDays) =>
        SubscriptionInvoice(
          id: 'inv-$id',
          planId: plan.id,
          planName: plan.name,
          amountMxn: plan.priceMxn,
          dueDate: now.add(Duration(days: dueInDays)),
          status: InvoiceStatus.pendiente,
        );
    final e = plans[0], c = plans[1], k = plans[2];
    return [
      TenantSummary(
          id: 't-sol',
          code: '150467',
          name: 'Bodega El Sol',
          status: SubscriptionStatus.active,
          ownerEmail: 'sol@tiendita.mx',
          plan: c,
          createdAt: now.subtract(const Duration(days: 40)),
          pendingInvoice: inv('sol', c, 16)),
      TenantSummary(
          id: 't-pepe',
          code: '203311',
          name: 'Abarrotes Don Pepe',
          status: SubscriptionStatus.active,
          ownerEmail: 'pepe@tiendita.mx',
          plan: e,
          createdAt: now.subtract(const Duration(days: 120)),
          pendingInvoice: inv('pepe', e, 9)),
      TenantSummary(
          id: 't-lupita',
          code: '318902',
          name: 'Miscelánea Lupita',
          status: SubscriptionStatus.softLock,
          ownerEmail: 'lupita@tiendita.mx',
          plan: e,
          createdAt: now.subtract(const Duration(days: 75)),
          pendingInvoice: inv('lupita', e, -4),
          daysOverdue: 4),
      TenantSummary(
          id: 't-norte',
          code: '412255',
          name: 'Súper del Norte',
          status: SubscriptionStatus.active,
          ownerEmail: 'norte@tiendita.mx',
          plan: k,
          createdAt: now.subtract(const Duration(days: 200)),
          pendingInvoice: inv('norte', k, 22)),
      TenantSummary(
          id: 't-esquina',
          code: '509870',
          name: 'La Esquina',
          status: SubscriptionStatus.hardLock,
          ownerEmail: 'esquina@tiendita.mx',
          plan: c,
          createdAt: now.subtract(const Duration(days: 95)),
          pendingInvoice: inv('esquina', c, -13),
          daysOverdue: 13),
      TenantSummary(
          id: 't-mary',
          code: '611004',
          name: 'Cremería Mary',
          status: SubscriptionStatus.active,
          ownerEmail: 'mary@tiendita.mx',
          plan: c,
          createdAt: now.subtract(const Duration(days: 12)),
          pendingInvoice: inv('mary', c, 18)),
      TenantSummary(
          id: 't-tres',
          code: '720199',
          name: 'Tres Hermanos',
          status: SubscriptionStatus.active,
          ownerEmail: 'tres@tiendita.mx',
          plan: e,
          createdAt: now.subtract(const Duration(days: 5)),
          pendingInvoice: inv('tres', e, 25)),
      TenantSummary(
          id: 't-centro',
          code: '833120',
          name: 'Abarrotes Centro',
          status: SubscriptionStatus.softLock,
          ownerEmail: 'centro@tiendita.mx',
          plan: c,
          createdAt: now.subtract(const Duration(days: 300)),
          pendingInvoice: inv('centro', c, -9),
          daysOverdue: 9),
    ];
  }

  void _seedValidations() {
    void add(
        String tenantId, SaasPaymentMethod method, String ref, int minutesAgo) {
      final t = _tenants.firstWhere((x) => x.id == tenantId);
      final inv = t.pendingInvoice!;
      _validations.add(ValidationInboxItem(
        validation: PaymentValidation(
          id: 'val-${++_seq}',
          invoiceId: inv.id,
          method: method,
          reference: ref,
          status: ValidationStatus.pendiente,
          createdAt: now().subtract(Duration(minutes: minutesAgo)),
        ),
        tenantId: t.id,
        tenantCode: t.code,
        tenantName: t.name,
        invoiceAmountMxn: inv.amountMxn,
        invoiceDueDate: inv.dueDate,
      ));
    }

    add('t-lupita', SaasPaymentMethod.spei, 'RAST20260913A1', 180);
    add('t-esquina', SaasPaymentMethod.oxxo, '98765432109876', 45);
  }

  Future<T> _delay<T>(T value) => Future.delayed(latency, () => value);

  TenantSummary get _current =>
      _tenants.firstWhere((t) => t.id == currentTenantId);

  void _replace(TenantSummary updated) {
    _tenants = [for (final t in _tenants) t.id == updated.id ? updated : t];
  }

  Subscription _subscriptionOf(TenantSummary t) {
    final inv = t.pendingInvoice;
    final review = _validations
        .where((v) => v.tenantId == t.id && v.validation.invoiceId == inv?.id)
        .map((v) => v.validation)
        .toList()
      ..sort((a, b) => (b.createdAt ?? now()).compareTo(a.createdAt ?? now()));
    return Subscription(
      tenantId: t.id,
      tenantCode: t.code,
      tenantName: t.name,
      status: t.status,
      plan: t.plan,
      pendingInvoice: inv,
      pendingValidation: review.isEmpty ? null : review.first,
      daysOverdue: t.daysOverdue,
      softLockAt: inv?.dueDate.add(const Duration(days: 1)),
      hardLockAt: inv?.dueDate.add(const Duration(days: 11)),
      spei: inv == null
          ? null
          : SpeiInstructions(
              clabe: clabe,
              bank: bank,
              holder: holder,
              concept: t.code,
              amountMxn: inv.amountMxn,
            ),
      // El mock sí entrega OXXO para que la tarjeta exista y se pruebe;
      // el backend real devuelve null (sin proveedor).
      oxxo: inv == null || !includeOxxo
          ? null
          : OxxoInstructions(
              reference:
                  '93${t.code}${inv.amountMxn.round().toString().padLeft(6, '0')}',
              barcode:
                  '7501${t.code}${inv.amountMxn.round().toString().padLeft(6, '0')}0',
              expiresAt: inv.dueDate.add(const Duration(days: 10)),
            ),
    );
  }

  // --- Comerciante ---

  @override
  Future<SaasProfile> getProfile() {
    final t = _current;
    return _delay(SaasProfile(
      email: currentEmail,
      permissions: isFounder ? const ['saas.manage'] : const [],
      isFounder: isFounder,
      tenantCode: t.code,
      tenantName: t.name,
      status: t.status,
      roleName: 'TENANT_OWNER',
      planId: t.plan?.id,
    ));
  }

  @override
  Future<List<SaasPlan>> getPlans() => _delay(plans);

  @override
  Future<Subscription> getSubscription() => _delay(_subscriptionOf(_current));

  @override
  Future<List<SubscriptionInvoice>> getInvoices() {
    final t = _current;
    final own = _invoices
        .where((i) => i.id.contains(t.id.substring(2)))
        .toList()
      ..sort((a, b) => b.dueDate.compareTo(a.dueDate));
    // Historial demo: dos meses pagados antes de la pendiente.
    final plan = t.plan ?? plans[1];
    final paid = [
      for (var m = 1; m <= 2; m++)
        SubscriptionInvoice(
          id: 'inv-${t.id}-paid-$m',
          planId: plan.id,
          planName: plan.name,
          amountMxn: plan.priceMxn,
          dueDate: addMonths(t.pendingInvoice?.dueDate ?? now(), -m),
          status: InvoiceStatus.pagada,
        ),
    ];
    return _delay([...own, ...paid]);
  }

  @override
  Future<Subscription> changePlan(String planId) async {
    final plan = plans.firstWhere(
      (p) => p.id == planId,
      orElse: () =>
          throw const SaasException('Plan no encontrado.', statusCode: 404),
    );
    final t = _current;
    final sub = _subscriptionOf(t);
    if (sub.hasPaymentInReview) {
      throw const SaasException(
        'Tienes un aviso de pago en revisión. Espera la validación antes de cambiar de plan.',
        statusCode: 422,
      );
    }
    final inv = t.pendingInvoice;
    final newInv = inv == null
        ? null
        : SubscriptionInvoice(
            id: inv.id,
            planId: plan.id,
            planName: plan.name,
            amountMxn: plan.priceMxn,
            dueDate: inv.dueDate,
            status: inv.status,
          );
    _replace(t.copyWith(plan: plan, pendingInvoice: newInv));
    if (newInv != null) {
      final idx = _invoices.indexWhere((i) => i.id == newInv.id);
      if (idx >= 0) _invoices[idx] = newInv;
    }
    return _delay(_subscriptionOf(_current));
  }

  @override
  Future<PaymentValidation> reportPayment({
    required String invoiceId,
    required SaasPaymentMethod method,
    required String reference,
  }) async {
    final t = _current;
    final inv = t.pendingInvoice;
    if (inv == null || inv.id != invoiceId) {
      throw const SaasException('Factura no encontrada.', statusCode: 404);
    }
    if (_validations.any((v) =>
        v.validation.invoiceId == invoiceId &&
        v.validation.status == ValidationStatus.pendiente)) {
      throw const SaasException(
        'Ya recibimos un aviso de pago para esta factura; está en revisión.',
        statusCode: 422,
      );
    }
    if (reference.trim().length < 4) {
      throw const SaasException(
          'Escribe la referencia o clave de rastreo (mínimo 4 caracteres).',
          statusCode: 422);
    }
    final validation = PaymentValidation(
      id: 'val-${++_seq}',
      invoiceId: inv.id,
      method: method,
      reference: reference.trim(),
      status: ValidationStatus.pendiente,
      createdAt: now(),
    );
    _validations.add(ValidationInboxItem(
      validation: validation,
      tenantId: t.id,
      tenantCode: t.code,
      tenantName: t.name,
      invoiceAmountMxn: inv.amountMxn,
      invoiceDueDate: inv.dueDate,
    ));
    return _delay(validation);
  }

  @override
  Future<List<PaymentValidation>> getMyValidations() {
    final list = _validations
        .where((v) => v.tenantId == currentTenantId)
        .map((v) => v.validation)
        .toList()
      ..sort((a, b) => (b.createdAt ?? now()).compareTo(a.createdAt ?? now()));
    return _delay(list);
  }

  // --- Fundadores ---

  void _requireFounder() {
    if (!isFounder) {
      throw const SaasException(
        'Este panel es exclusivo de los fundadores de Nexus.',
        code: 'SAAS_FOUNDER_ONLY',
        statusCode: 403,
      );
    }
  }

  @override
  Future<FounderMetrics> getFounderMetrics() {
    _requireFounder();
    final active = _tenants.where((t) => t.status == SubscriptionStatus.active);
    final mrr =
        active.fold<double>(0, (sum, t) => sum + (t.plan?.priceMxn ?? 0));
    final soft =
        _tenants.where((t) => t.status == SubscriptionStatus.softLock).length;
    final hard =
        _tenants.where((t) => t.status == SubscriptionStatus.hardLock).length;
    final cutoff = now().subtract(const Duration(days: 30));
    return _delay(FounderMetrics(
      mrrMxn: mrr,
      tenantsTotal: _tenants.length,
      tenantsActive: active.length,
      tenantsSoftLock: soft,
      tenantsHardLock: hard,
      newTenants30d:
          _tenants.where((t) => (t.createdAt ?? now()).isAfter(cutoff)).length,
      pendingValidations: _validations
          .where((v) => v.validation.status == ValidationStatus.pendiente)
          .length,
      retentionRate: _tenants.isEmpty ? 0 : active.length / _tenants.length,
    ));
  }

  @override
  Future<List<TenantSummary>> getTenants(TenantFilter filter) {
    _requireFounder();
    final q = filter.query.trim().toLowerCase();
    final list = _tenants.where((t) {
      if (filter.status != null && t.status != filter.status) return false;
      if (filter.planId != null && t.plan?.id != filter.planId) return false;
      if (q.isNotEmpty &&
          !t.name.toLowerCase().contains(q) &&
          !t.code.toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => (b.createdAt ?? now()).compareTo(a.createdAt ?? now()));
    return _delay(list);
  }

  @override
  Future<List<ValidationInboxItem>> getValidationInbox() {
    _requireFounder();
    final list = _validations
        .where((v) => v.validation.status == ValidationStatus.pendiente)
        .toList()
      ..sort((a, b) => (a.validation.createdAt ?? now())
          .compareTo(b.validation.createdAt ?? now()));
    return _delay(list);
  }

  ValidationInboxItem _pendingById(String id) {
    final idx = _validations.indexWhere((v) => v.validation.id == id);
    if (idx < 0) {
      throw const SaasException('Aviso de pago no encontrado.',
          statusCode: 404);
    }
    final item = _validations[idx];
    if (item.validation.status != ValidationStatus.pendiente) {
      throw SaasException(
          'Este aviso ya fue resuelto (${item.validation.status.label}).',
          statusCode: 422);
    }
    return item;
  }

  void _resolve(
      ValidationInboxItem item, ValidationStatus status, String? notes) {
    final idx =
        _validations.indexWhere((v) => v.validation.id == item.validation.id);
    final v = item.validation;
    _validations[idx] = ValidationInboxItem(
      validation: PaymentValidation(
        id: v.id,
        invoiceId: v.invoiceId,
        method: v.method,
        reference: v.reference,
        status: status,
        receiptUrl: v.receiptUrl,
        notes: notes,
        createdAt: v.createdAt,
        updatedAt: now(),
      ),
      tenantId: item.tenantId,
      tenantCode: item.tenantCode,
      tenantName: item.tenantName,
      invoiceAmountMxn: item.invoiceAmountMxn,
      invoiceDueDate: item.invoiceDueDate,
    );
  }

  @override
  Future<void> approveValidation(String validationId, {String? notes}) async {
    _requireFounder();
    final item = _pendingById(validationId);
    _resolve(item, ValidationStatus.aprobada, notes);
    final t = _tenants.firstWhere((x) => x.id == item.tenantId);
    final paidInv = t.pendingInvoice!;
    final plan = t.plan ?? plans[1];
    // Factura pagada + comercio ACTIVE + siguiente periodo generado.
    final idx = _invoices.indexWhere((i) => i.id == paidInv.id);
    final paid = SubscriptionInvoice(
      id: paidInv.id,
      planId: paidInv.planId,
      planName: paidInv.planName,
      amountMxn: paidInv.amountMxn,
      dueDate: paidInv.dueDate,
      status: InvoiceStatus.pagada,
    );
    if (idx >= 0) _invoices[idx] = paid;
    final next = SubscriptionInvoice(
      id: 'inv-${t.id.substring(2)}-${++_seq}',
      planId: plan.id,
      planName: plan.name,
      amountMxn: plan.priceMxn,
      dueDate: addMonths(paidInv.dueDate, 1),
      status: InvoiceStatus.pendiente,
    );
    _invoices.add(next);
    _replace(t.copyWith(
      status: SubscriptionStatus.active,
      pendingInvoice: next,
      daysOverdue: 0,
      lastValidation: _validations[
              _validations.indexWhere((v) => v.validation.id == validationId)]
          .validation,
    ));
    await _delay(null);
  }

  @override
  Future<void> rejectValidation(String validationId,
      {required String notes}) async {
    _requireFounder();
    if (notes.trim().length < 3) {
      throw const SaasException('Escribe el motivo del rechazo.',
          statusCode: 422);
    }
    final item = _pendingById(validationId);
    _resolve(item, ValidationStatus.rechazada, notes.trim());
    final t = _tenants.firstWhere((x) => x.id == item.tenantId);
    _replace(t.copyWith(
      lastValidation: _validations[
              _validations.indexWhere((v) => v.validation.id == validationId)]
          .validation,
    ));
    await _delay(null);
  }

  @override
  Future<TenantSummary> setTenantStatus(
      String tenantId, SubscriptionStatus status) async {
    _requireFounder();
    final t = _tenants.firstWhere(
      (x) => x.id == tenantId,
      orElse: () =>
          throw const SaasException('Comercio no encontrado.', statusCode: 404),
    );
    var inv = t.pendingInvoice;
    var overdue = t.daysOverdue;
    if (status == SubscriptionStatus.active && inv != null && overdue > 0) {
      // Igual que el backend: reactivar corre el vencimiento 7 días.
      inv = SubscriptionInvoice(
        id: inv.id,
        planId: inv.planId,
        planName: inv.planName,
        amountMxn: inv.amountMxn,
        dueDate: now().add(const Duration(days: 7)),
        status: inv.status,
      );
      overdue = 0;
    }
    final updated =
        t.copyWith(status: status, pendingInvoice: inv, daysOverdue: overdue);
    _replace(updated);
    return _delay(updated);
  }

  @override
  Future<SubscriptionInvoice> extendDueDate(String tenantId, int days) async {
    _requireFounder();
    final t = _tenants.firstWhere((x) => x.id == tenantId);
    final inv = t.pendingInvoice;
    if (inv == null) {
      throw const SaasException(
          'El comercio no tiene factura pendiente que extender.',
          statusCode: 404);
    }
    final base = inv.dueDate.isAfter(now()) ? inv.dueDate : now();
    final extended = SubscriptionInvoice(
      id: inv.id,
      planId: inv.planId,
      planName: inv.planName,
      amountMxn: inv.amountMxn,
      dueDate: base.add(Duration(days: days)),
      status: inv.status,
    );
    _replace(t.copyWith(
      pendingInvoice: extended,
      daysOverdue: 0,
      status: SubscriptionStatus.active,
    ));
    return _delay(extended);
  }
}
