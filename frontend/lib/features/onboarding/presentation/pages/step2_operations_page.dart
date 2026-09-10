import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/app_colors.dart';
import '../onboarding_provider.dart';

/// Paso 2 — Configuración Operativa
/// Referencia: campo almacén con default + campo ticket + chips sugeridos + preview recibo
class Step2OperationsPage extends ConsumerStatefulWidget {
  const Step2OperationsPage({super.key});

  @override
  ConsumerState<Step2OperationsPage> createState() =>
      _Step2OperationsPageState();
}

class _Step2OperationsPageState extends ConsumerState<Step2OperationsPage> {
  late final TextEditingController _warehouseCtrl;
  late final TextEditingController _ticketCtrl;

  static const _suggestions = [
    '¡Gracias por preferirnos!',
    'Vuelva pronto',
    'Conserve su ticket',
  ];

  @override
  void initState() {
    super.initState();
    final data = ref.read(onboardingProvider).data;
    _warehouseCtrl = TextEditingController(text: data.warehouseName);
    _ticketCtrl = TextEditingController(text: data.ticketHeader);
  }

  @override
  void dispose() {
    _warehouseCtrl.dispose();
    _ticketCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(onboardingProvider).data;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          _buildHeadline(context),
          const SizedBox(height: 32),
          _buildWarehouseField(),
          const SizedBox(height: 8),
          _buildHint('Puedes añadir más almacenes después'),
          const SizedBox(height: 24),
          _buildTicketField(data),
          const SizedBox(height: 12),
          _buildSuggestions(),
          const SizedBox(height: 24),
          _buildReceiptPreview(data),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ---------- Secciones ----------

  Widget _buildHeadline(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '¿Desde dónde operarás?',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 10),
        Text(
          'Define el almacén inicial y el mensaje de tus recibos.\nTodo es editable después.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.onSurfaceMuted,
                height: 1.5,
              ),
        ),
      ],
    );
  }

  Widget _buildWarehouseField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'NOMBRE DE TU ALMACÉN PRINCIPAL',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.onSurfaceMuted,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _warehouseCtrl,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: AppColors.onSurface,
          ),
          decoration: InputDecoration(
            hintText: 'Bodega Central',
            prefixIcon: const Icon(
              Icons.warehouse_rounded,
              size: 20,
              color: AppColors.onSurfaceMuted,
            ),
            suffixIcon: ValueListenableBuilder(
              valueListenable: _warehouseCtrl,
              builder: (_, v, __) => v.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.cancel_rounded,
                          size: 18, color: AppColors.onSurfaceMuted),
                      onPressed: () {
                        _warehouseCtrl.clear();
                        ref
                            .read(onboardingProvider.notifier)
                            .setWarehouseName('');
                      },
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          onChanged: (v) =>
              ref.read(onboardingProvider.notifier).setWarehouseName(v),
        ),
      ],
    );
  }

  Widget _buildTicketField(data) {
    final charCount = (data.ticketHeader as String).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'ENCABEZADO PARA TUS TICKETS DE VENTA',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurfaceMuted,
                letterSpacing: 1.0,
              ),
            ),
            const Spacer(),
            Text(
              '$charCount / 40',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.onSurfaceMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _ticketCtrl,
          maxLength: 40,
          textInputAction: TextInputAction.done,
          style: const TextStyle(
            fontSize: 15,
            color: AppColors.onSurface,
          ),
          decoration: const InputDecoration(
            hintText: 'Ej. ¡Gracias por su compra!',
            prefixIcon: Icon(
              Icons.receipt_long_rounded,
              size: 20,
              color: AppColors.onSurfaceMuted,
            ),
            counterText: '',
          ),
          onChanged: (v) =>
              ref.read(onboardingProvider.notifier).setTicketHeader(v),
        ),
      ],
    );
  }

  Widget _buildSuggestions() {
    return Wrap(
      spacing: 8,
      children: _suggestions
          .map(
            (s) => ActionChip(
              label: Text(s),
              labelStyle: const TextStyle(
                fontSize: 12,
                color: AppColors.onSurface,
              ),
              backgroundColor: AppColors.surfaceVariant,
              side: const BorderSide(color: AppColors.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              onPressed: () {
                _ticketCtrl.text = s;
                ref.read(onboardingProvider.notifier).setTicketHeader(s);
              },
            ),
          )
          .toList(),
    );
  }

  Widget _buildReceiptPreview(data) {
    final businessName = ref.read(onboardingProvider).data.businessName.isEmpty
        ? 'NEXUS STORE'
        : ref.read(onboardingProvider).data.businessName.toUpperCase();
    final header = (data.ticketHeader as String).isEmpty
        ? '¡Gracias por su compra!'
        : data.ticketHeader as String;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          // Header de la preview
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                const Icon(Icons.visibility_outlined,
                    size: 14, color: AppColors.emerald),
                const SizedBox(width: 6),
                const Text(
                  'Vista previa de recibo',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '80MM POS',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurfaceMuted,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Contenido simulado del ticket
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  businessName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.onSurface,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  header,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.onSurfaceMuted,
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(color: AppColors.border, height: 1),
                const SizedBox(height: 12),
                const Row(
                  children: [
                    Text('1x Producto Demo',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.onSurface)),
                    Spacer(),
                    Text(r'$12.500',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.onSurface)),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(color: AppColors.border, height: 1),
                const SizedBox(height: 12),
                const Row(
                  children: [
                    Text('Total',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.onSurface)),
                    Spacer(),
                    Text(r'$12.500',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.onSurface)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHint(String text) {
    return Row(
      children: [
        const Icon(Icons.info_outline_rounded,
            size: 14, color: AppColors.onSurfaceMuted),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.onSurfaceMuted,
          ),
        ),
      ],
    );
  }
}
