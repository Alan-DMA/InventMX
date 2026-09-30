import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/network/auth_interceptor.dart';
import 'package:nexus_app/features/auth/data/auth_repository.dart';
import 'package:nexus_app/features/auth/domain/auth_token.dart';
import 'package:nexus_app/features/auth/presentation/login_provider.dart';
import 'package:nexus_app/features/auth/presentation/server_signals.dart';
import 'package:nexus_app/features/saas_admin/data/saas_repository.dart';
import 'package:nexus_app/features/saas_admin/domain/subscription.dart';
import 'package:nexus_app/features/saas_admin/presentation/saas_provider.dart';
import 'package:nexus_app/features/support/domain/support_models.dart';

import 'support_app_harness.dart' show MemoryStorage;

void main() {
  group('HelpTopic', () {
    test('el cuerpo del servidor se parte en párrafos y listas', () {
      final topic = HelpTopic.fromJson(const {
        'key': 'something_broken',
        'title': 'Algo no funciona',
        'body': 'Antes de escribirnos, prueba esto:\n\n• Revisa que tengas internet.\n• Cierra la app.\n\n'
            'Si sigue pasando, cuéntanos.',
        'actions': [
          {'label': 'Ver Mi suscripción', 'target': 'subscription'},
        ],
        'form_fields': [
          {'key': 'module', 'label': '¿Dónde?', 'type': 'select', 'required': true, 'options': ['Caja', 'Ventas']},
          {'key': 'when', 'label': '¿Cuándo?', 'type': 'desconocido'},
        ],
      });
      expect(topic.blocks, const [
        HelpBlock.paragraph('Antes de escribirnos, prueba esto:'),
        HelpBlock.bullets(['Revisa que tengas internet.', 'Cierra la app.']),
        HelpBlock.paragraph('Si sigue pasando, cuéntanos.'),
      ]);
      expect(topic.formFields.first.type, FormFieldType.select);
      expect(topic.formFields.first.options, ['Caja', 'Ventas']);
      // Un tipo nuevo que la app no conoce se pinta como texto, no rompe
      expect(topic.formFields.last.type, FormFieldType.text);
      expect(topic.actions.single.target, 'subscription');
    });
  });

  test('SupportCase lee lo que manda el backend', () {
    final c = SupportCase.fromJson(const {
      'id': 'c1',
      'number': 1042,
      'topic_key': 'other',
      'topic_title': 'Otra pregunta',
      'status': 'ANSWERED',
      'unread': true,
      'is_mine': false,
      'author_name': 'Lupita',
      'created_at': '2026-09-28T15:00:00Z',
      'last_message_at': '2026-09-28T16:30:00Z',
      'answers': [
        {'key': 'module', 'label': '¿Dónde?', 'value': 'Caja'},
      ],
      'messages': [
        {'id': 'm1', 'author_kind': 'SUPPORT', 'author_name': 'Soporte Nexus · Eduardo', 'body': 'Hola', 'created_at': '2026-09-28T16:30:00Z'},
      ],
    });
    expect(c.status, CaseStatus.answered);
    expect(c.status.label, 'Respondido');
    expect(c.unread && !c.isMine, isTrue);
    expect(c.messages.single.fromSupport, isTrue);
    expect(c.answers.single.value, 'Caja');
  });

  test('AuthToken sabe si el login fue con código', () {
    final token = AuthToken.fromJson(const {
      'access_token': 'a',
      'refresh_token': 'r',
      'user': {'must_change_password': true},
    });
    expect(token.mustChangePassword, isTrue);
    expect(AuthToken.fromJson(const {'access_token': 'a', 'refresh_token': 'r'}).mustChangePassword, isFalse);
  });

  test('Subscription: la suspensión por abuso nunca ofrece renovar', () {
    final abuse = Subscription.fromJson(const {
      'status': 'HARD_LOCK',
      'lock_reason': 'ABUSE',
      'suspension_reason': 'Motivo',
      'renewal_channel': 'GOOGLE_PLAY',
    });
    expect(abuse.isAbuseSuspension, isTrue);
    expect(abuse.canRenewInApp, isFalse);
    final unpaid = Subscription.fromJson(const {'status': 'HARD_LOCK', 'lock_reason': 'NONPAYMENT', 'renewal_channel': 'GOOGLE_PLAY'});
    expect(unpaid.isAbuseSuspension, isFalse);
    expect(unpaid.canRenewInApp, isTrue);
  });

  group('señales del servidor', () {
    ProviderContainer container(MemoryStorage storage, SaasRepositoryMock saas) {
      final c = ProviderContainer(overrides: [
        secureStorageProvider.overrideWithValue(storage),
        sessionProvider.overrideWith((ref) => true),
        saasRepositoryProvider.overrideWithValue(saas),
        serverSignalHandlerProvider.overrideWith((ref) => (code) => handleServerSignal(ref, code)),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('403 PASSWORD_CHANGE_REQUIRED enciende y guarda el cambio pendiente', () async {
      final storage = MemoryStorage();
      final c = container(storage, SaasRepositoryMock(latency: Duration.zero));
      c.read(serverSignalHandlerProvider)(AuthInterceptor.passwordChangeRequired);
      expect(c.read(mustChangePasswordProvider), isTrue);
      expect(await storage.readMustChangePassword(), isTrue);
    });

    test('402 TENANT_HARD_LOCK con la app abierta relee la suscripción', () async {
      final saas = SaasRepositoryMock(latency: Duration.zero, daysUntilDue: 20);
      final c = container(MemoryStorage(), saas);
      await c.read(subscriptionProvider.future);
      expect(c.read(subscriptionStatusProvider), SubscriptionStatus.active);

      saas.daysUntilDue = -30; // la suspendieron mientras estaba abierta
      c.read(serverSignalHandlerProvider)(AuthInterceptor.tenantHardLock);
      await Future<void>.delayed(Duration.zero);
      await c.read(subscriptionProvider.future);
      expect(c.read(subscriptionStatusProvider), SubscriptionStatus.hardLock);
    });
  });
}
