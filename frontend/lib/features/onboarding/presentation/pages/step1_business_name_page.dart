import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/app_colors.dart';
import '../onboarding_provider.dart';

/// Paso 1 — Datos del Comercio
/// Referencia visual: ícono de cámara centrado + campo nombre tienda
class Step1BusinessNamePage extends ConsumerStatefulWidget {
  const Step1BusinessNamePage({super.key});

  @override
  ConsumerState<Step1BusinessNamePage> createState() =>
      _Step1BusinessNamePageState();
}

class _Step1BusinessNamePageState extends ConsumerState<Step1BusinessNamePage> {
  late final TextEditingController _nameCtrl;
  late final FocusNode _nameFocus;

  @override
  void initState() {
    super.initState();
    final current = ref.read(onboardingProvider).data.businessName;
    _nameCtrl = TextEditingController(text: current);
    _nameFocus = FocusNode();
    // Foco automático al entrar al paso
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nameFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          _buildHeadline(context),
          const SizedBox(height: 40),
          _buildLogoPicker(),
          const SizedBox(height: 40),
          _buildNameField(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ---------- Headline ----------

  Widget _buildHeadline(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '¡Bienvenido a Nexus!\nEmpecemos por tu negocio.',
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                height: 1.25,
              ),
        ),
        const SizedBox(height: 10),
        Text(
          'Configura los datos básicos de tu tienda.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.onSurfaceMuted,
              ),
        ),
      ],
    );
  }

  // ---------- Logo picker ----------

  Widget _buildLogoPicker() {
    return Center(
      child: Column(
        children: [
          // Sin GestureDetector — no-interactivo en esta fase.
          // El logo se configura desde el perfil del comercio (módulo futuro).
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.border,
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.photo_camera_outlined,
                  size: 36,
                  color: AppColors.onSurfaceMuted,
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Icon(
                    Icons.add,
                    size: 16,
                    color: AppColors.onSurfaceMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Foto o logo del comercio',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Opcional · JPG o PNG',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.onSurfaceMuted,
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Nombre ----------

  Widget _buildNameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'NOMBRE DE LA TIENDA',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.onSurfaceMuted,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _nameCtrl,
          focusNode: _nameFocus,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: AppColors.onSurface,
          ),
          decoration: InputDecoration(
            hintText: 'Ej. Abarrotes San Miguel',
            prefixIcon: const Icon(
              Icons.storefront_rounded,
              size: 20,
              color: AppColors.onSurfaceMuted,
            ),
            suffixIcon: ValueListenableBuilder(
              valueListenable: _nameCtrl,
              builder: (_, value, __) => value.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.cancel_rounded,
                          size: 18, color: AppColors.onSurfaceMuted),
                      onPressed: () {
                        _nameCtrl.clear();
                        ref
                            .read(onboardingProvider.notifier)
                            .setBusinessName('');
                      },
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          onChanged: (v) =>
              ref.read(onboardingProvider.notifier).setBusinessName(v),
        ),
      ],
    );
  }

  // ---------- Acciones ----------
  // Logo picker sin implementación en esta fase.
  // Se activa desde el perfil del comercio cuando se complete ese módulo.
}
