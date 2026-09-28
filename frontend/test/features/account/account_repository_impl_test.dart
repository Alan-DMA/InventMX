// Cambio de contraseña contra el servidor real (Ajustes operativos, D9):
// `POST /auth/change-password` con la actual; 400 → contraseña actual
// incorrecta.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nexus_app/core/network/dio_client.dart';
import 'package:nexus_app/features/account/data/account_repository.dart';

class MockDioClient extends Mock implements DioClient {}

const _path = '/api/v1/auth/change-password';

void main() {
  late MockDioClient client;
  late AccountRepositoryImpl repo;

  setUp(() {
    client = MockDioClient();
    repo = AccountRepositoryImpl(client: client);
  });

  void stubPost(Future<Response<dynamic>> Function() answer) {
    when(() => client.post<dynamic>(
          _path,
          data: any(named: 'data'),
          options: any(named: 'options'),
        )).thenAnswer((_) => answer());
  }

  test('manda la actual y la nueva (CA-A1)', () async {
    stubPost(() async => Response(
        statusCode: 204, requestOptions: RequestOptions(path: _path)));

    await repo.changePassword(
        currentPassword: 'Cajero123', newPassword: 'nuevaClave99');

    final sent = verify(() => client.post<dynamic>(
          _path,
          data: captureAny(named: 'data'),
          options: any(named: 'options'),
        )).captured.single as Map;
    expect(sent, {
      'current_password': 'Cajero123',
      'new_password': 'nuevaClave99',
    });
  });

  test('400 → la contraseña actual no es correcta', () async {
    stubPost(() async => throw DioException(
          requestOptions: RequestOptions(path: _path),
          response: Response(
            statusCode: 400,
            data: {
              'success': false,
              'error': {'message': 'La contraseña actual no es correcta.'},
            },
            requestOptions: RequestOptions(path: _path),
          ),
          type: DioExceptionType.badResponse,
        ));

    await expectLater(
      repo.changePassword(currentPassword: 'mala', newPassword: 'nuevaClave99'),
      throwsA(isA<WrongCurrentPasswordException>()),
    );
  });

  test('sin red se dice así, no como contraseña incorrecta', () async {
    stubPost(() async => throw DioException(
          requestOptions: RequestOptions(path: _path),
          type: DioExceptionType.connectionError,
        ));

    await expectLater(
      repo.changePassword(
          currentPassword: 'Cajero123', newPassword: 'nuevaClave99'),
      throwsA(predicate((e) => e.toString().contains('Sin conexión'))),
    );
  });
}
