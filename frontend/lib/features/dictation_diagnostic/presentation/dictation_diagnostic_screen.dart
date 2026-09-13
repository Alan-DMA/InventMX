import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../purchases/presentation/purchases_provider.dart';

/// Pantalla de DIAGNÓSTICO del prototipo CRF de dictado multi-ítem — Fase 3.
///
/// No es una pantalla de producto: valida el prototipo de
/// `prototypes/dictation_crf/` (fuera del alcance formal de `CLAUDE.md`,
/// ver `docs/architecture/registro_implementacion.md`, sección "EXPLORACIÓN
/// ACTIVA"). Por eso NO pasa por `/intent`/`/impeccable` ni se enlaza desde
/// la navegación real — solo se llega a ella por URL directa
/// (`/diagnostic/dictation`), ver `AppRoutes.dictationDiagnostic`.
///
/// Envía el transcript crudo (dictado o escrito a mano) al servidor local
/// `server.py` (Fase 3) en vez de `VoiceDictationParser`, para comparar el
/// enfoque CRF contra frases reales.
class DictationDiagnosticScreen extends ConsumerStatefulWidget {
  const DictationDiagnosticScreen({super.key});

  @override
  ConsumerState<DictationDiagnosticScreen> createState() =>
      _DictationDiagnosticScreenState();
}

class _DictationDiagnosticScreenState
    extends ConsumerState<DictationDiagnosticScreen> {
  final _serverUrlController =
      TextEditingController(text: 'http://localhost:8000');
  final _manualTextController = TextEditingController();
  final _dio = Dio();

  bool _isListening = false;
  String _partialTranscript = '';
  bool _isSending = false;
  String? _errorMessage;

  List<String>? _tokens;
  List<String>? _tags;
  List<Map<String, dynamic>>? _items;

  @override
  void dispose() {
    _serverUrlController.dispose();
    _manualTextController.dispose();
    _dio.close();
    super.dispose();
  }

  Future<void> _toggleDictation() async {
    final service = ref.read(voiceDictationServiceProvider);

    if (_isListening) {
      await service.stop();
      setState(() => _isListening = false);
      return;
    }

    final ready = await service.initialize();
    if (!ready) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo iniciar el reconocimiento de voz'),
        ),
      );
      return;
    }

    setState(() {
      _isListening = true;
      _partialTranscript = '';
    });

    await service.listen(
      onResult: (transcript, isFinal) {
        if (!mounted) return;
        setState(() => _partialTranscript = transcript);
        if (isFinal) {
          setState(() => _isListening = false);
          if (transcript.trim().isNotEmpty) {
            _sendToServer(transcript);
          }
        }
      },
    );
  }

  Future<void> _sendToServer(String text) async {
    final baseUrl = _serverUrlController.text.trim();
    setState(() {
      _isSending = true;
      _errorMessage = null;
      _tokens = null;
      _tags = null;
      _items = null;
    });

    try {
      final response = await _dio.post(
        '$baseUrl/parse',
        data: {'text': text},
        options: Options(
          headers: {'Content-Type': 'application/json'},
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
      final data = response.data as Map<String, dynamic>;
      setState(() {
        _tokens = List<String>.from(data['tokens'] as List);
        _tags = List<String>.from(data['tags'] as List);
        _items = List<Map<String, dynamic>>.from(
          (data['items'] as List).map((e) => Map<String, dynamic>.from(e)),
        );
      });
    } on DioException catch (e) {
      setState(() {
        _errorMessage = 'No se pudo contactar $baseUrl — ${e.message}';
      });
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnóstico — Dictado CRF (prototipo)'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Herramienta interna — no es una feature de producto. '
                'Prueba el modelo CRF de prototypes/dictation_crf/ contra '
                'dictados reales.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _serverUrlController,
                decoration: const InputDecoration(
                  labelText: 'URL del servidor de diagnóstico',
                  hintText: 'http://localhost:8000',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _manualTextController,
                      decoration: const InputDecoration(
                        labelText: 'O escribe la frase a mano',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: _sendToServer,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.send),
                    tooltip: 'Enviar',
                    onPressed: () {
                      final text = _manualTextController.text;
                      if (text.trim().isNotEmpty) _sendToServer(text);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Center(
                child: Column(
                  children: [
                    IconButton.filled(
                      iconSize: 48,
                      style: IconButton.styleFrom(
                        backgroundColor: _isListening
                            ? AppColors.error
                            : AppColors.emerald,
                        padding: const EdgeInsets.all(20),
                      ),
                      icon: Icon(_isListening ? Icons.stop : Icons.mic),
                      onPressed: _toggleDictation,
                    ),
                    const SizedBox(height: 8),
                    Text(_isListening ? 'Escuchando…' : 'Toca para dictar'),
                    if (_partialTranscript.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '"$_partialTranscript"',
                          style: const TextStyle(fontStyle: FontStyle.italic),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (_isSending) const Center(child: CircularProgressIndicator()),
              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: AppColors.error),
                  ),
                ),
              if (_items != null) ...[
                Text(
                  'Ítems reconstruidos (${_items!.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                for (final item in _items!)
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppColors.emerald,
                        child: Text(item['qty']?.toString() ?? '?'),
                      ),
                      title: Text(
                        (item['name'] as String?)?.isEmpty ?? true
                            ? '(sin nombre)'
                            : item['name'] as String,
                      ),
                      subtitle: Text('\$${item['price'] ?? '?'} MXN'),
                    ),
                  ),
                const SizedBox(height: 16),
                ExpansionTile(
                  title: const Text('Tags crudos (token → tag)'),
                  children: [
                    if (_tokens != null && _tags != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (var i = 0; i < _tokens!.length; i++)
                              Chip(
                                label: Text(
                                  '${_tokens![i]} → ${_tags![i]}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
