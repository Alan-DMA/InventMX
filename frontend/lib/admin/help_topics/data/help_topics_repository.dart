import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/admin_http.dart';
import '../domain/admin_help_topic.dart';

/// Temas de ayuda del Soporte del tendero (P27).
abstract class HelpTopicsRepository {
  /// GET /platform/help-topics — todos, activos o no.
  Future<List<AdminHelpTopic>> list();

  /// PUT /platform/help-topics/{key} — el texto nuevo; acciones y campos del
  /// formulario se reenvían tal cual (P29).
  Future<AdminHelpTopic> save(AdminHelpTopic original, HelpTopicDraft draft, {required String reason});
}

class HelpTopicsRepositoryImpl implements HelpTopicsRepository {
  HelpTopicsRepositoryImpl(this._dio);
  final Dio _dio;

  @override
  Future<List<AdminHelpTopic>> list() async {
    try {
      final res = await _dio.get('/help-topics');
      return [for (final t in res.data as List) AdminHelpTopic.fromJson(t as Map<String, dynamic>)];
    } catch (e) {
      throw toAdminError(e, 'No pudimos cargar los temas de ayuda.');
    }
  }

  @override
  Future<AdminHelpTopic> save(AdminHelpTopic original, HelpTopicDraft draft, {required String reason}) async {
    try {
      final res = await _dio.put('/help-topics/${original.key}', data: {
        'title': draft.title.trim(),
        'summary': draft.summary.trim(),
        'body': draft.body.trim(),
        'actions': original.rawActions,
        'form_fields': original.rawFormFields,
        'audience': draft.audience,
        'sort_order': draft.sortOrder,
        'is_active': draft.isActive,
        'reason': reason.trim(),
      });
      return AdminHelpTopic.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw toAdminError(e, 'No se guardó el tema.');
    }
  }
}

final helpTopicsRepositoryProvider =
    Provider<HelpTopicsRepository>((ref) => HelpTopicsRepositoryImpl(ref.watch(adminDioProvider)));
