// Importación de utilidades de conversión base64
import 'dart:convert';
// Importación del selector de archivos para multiplataforma
import 'package:file_picker/file_picker.dart';
// Importación de widgets fundamentales de Flutter
import 'package:flutter/material.dart';
// Importación de Riverpod para inyección de dependencias
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Importación de la paleta de colores del sistema
import '../../../../../core/theme/app_colors.dart';
// Importación del provider de estado de onboarding
import '../onboarding_provider.dart';

/// Paso 1 — Datos del Comercio
/// Referencia visual: ícono de cámara / logo centrado + botón de subida + campo nombre tienda
class Step1BusinessNamePage extends ConsumerStatefulWidget {
  const Step1BusinessNamePage({super.key});

  @override
  ConsumerState<Step1BusinessNamePage> createState() =>
      _Step1BusinessNamePageState();
}

class _Step1BusinessNamePageState extends ConsumerState<Step1BusinessNamePage> {
  // Controlador de texto para el nombre del comercio
  late final TextEditingController _nameCtrl;
  // Nodo de foco para enfocar automáticamente el campo de texto
  late final FocusNode _nameFocus;
  // Estado local para indicar si se está procesando la selección de imagen
  bool _isPickingImage = false;

  @override
  void initState() {
    super.initState();
    // Obtiene el nombre guardado previamente en el provider
    final current = ref.read(onboardingProvider).data.businessName;
    _nameCtrl = TextEditingController(text: current);
    _nameFocus = FocusNode();
    // Foco automático al entrar al paso tras renderizar el primer frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nameFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    // Liberación de recursos del controlador y nodo de foco
    _nameCtrl.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  /// Función para abrir el selector de archivos y cargar la imagen del logo
  Future<void> _pickLogo() async {
    // Evita múltiples aperturas simultáneas
    if (_isPickingImage) return;

    setState(() {
      _isPickingImage = true;
    });

    try {
      // Abre el selector de archivos filtrando únicamente por imágenes
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );

      // Si el usuario seleccionó un archivo válido
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        
        // En Web y móvil con bytes disponibles
        if (file.bytes != null) {
          final base64Str = base64Encode(file.bytes!);
          final extension = (file.extension ?? 'png').toLowerCase();
          final mimeType = extension == 'png' ? 'image/png' : 'image/jpeg';
          final dataUri = 'data:$mimeType;base64,$base64Str';
          
          // Actualiza el estado global de onboarding con la imagen codificada
          ref.read(onboardingProvider.notifier).setLogoPath(dataUri);
        } else if (file.path != null && file.path!.isNotEmpty) {
          // En plataformas de escritorio con ruta de archivo local
          ref.read(onboardingProvider.notifier).setLogoPath(file.path);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al seleccionar la imagen: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPickingImage = false;
        });
      }
    }
  }

  /// Elimina el logo seleccionado
  void _removeLogo() {
    ref.read(onboardingProvider.notifier).setLogoPath(null);
  }

  @override
  Widget build(BuildContext context) {
    final onboardingState = ref.watch(onboardingProvider);
    final logoPath = onboardingState.data.logoPath;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          _buildHeadline(context),
          const SizedBox(height: 32),
          _buildLogoPicker(logoPath),
          const SizedBox(height: 32),
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

  Widget _buildLogoPicker(String? logoPath) {
    final hasLogo = logoPath != null && logoPath.isNotEmpty;

    return Center(
      child: Column(
        children: [
          // Selector circular interactivo con animación táctil
          InkWell(
            onTap: _isPickingImage ? null : _pickLogo,
            borderRadius: BorderRadius.circular(44),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: hasLogo ? AppColors.emerald : AppColors.border,
                      width: hasLogo ? 2.0 : 1.5,
                    ),
                  ),
                  child: _isPickingImage
                      ? const Center(
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: AppColors.emerald,
                            ),
                          ),
                        )
                      : _buildLogoPreview(logoPath),
                ),
                // Botón de insignia circular (+) o (editar)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: hasLogo ? AppColors.emerald : AppColors.surfaceVariant,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: hasLogo ? Colors.transparent : AppColors.border,
                      ),
                    ),
                    child: Icon(
                      hasLogo ? Icons.edit_rounded : Icons.add,
                      size: 16,
                      color: hasLogo ? Colors.white : AppColors.onSurfaceMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Botón interactivo acorde a la referencia UI Design
          OutlinedButton.icon(
            onPressed: _isPickingImage ? null : _pickLogo,
            icon: Icon(
              hasLogo
                  ? Icons.photo_library_outlined
                  : Icons.add_photo_alternate_outlined,
              size: 18,
              color: AppColors.emerald,
            ),
            label: Text(
              hasLogo
                  ? 'Cambiar logo del comercio'
                  : 'Subir logo de tu comercio (opcional)',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.emerald,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: AppColors.emerald.withValues(alpha: 0.5),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
          ),
          if (hasLogo) ...[
            const SizedBox(height: 6),
            TextButton(
              onPressed: _removeLogo,
              child: const Text(
                'Quitar imagen',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.error,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 6),
            const Text(
              'Opcional · Formato JPG o PNG',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.onSurfaceMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Construye la vista previa del logo cargado
  Widget _buildLogoPreview(String? logoPath) {
    if (logoPath == null || logoPath.isEmpty) {
      return const Icon(
        Icons.photo_camera_outlined,
        size: 36,
        color: AppColors.onSurfaceMuted,
      );
    }

    // Si es una Data URI en formato base64
    if (logoPath.startsWith('data:image')) {
      try {
        final commaIndex = logoPath.indexOf(',');
        final base64Data = commaIndex != -1 ? logoPath.substring(commaIndex + 1) : logoPath;
        final bytes = base64Decode(base64Data);
        return ClipOval(
          child: Image.memory(
            bytes,
            width: 88,
            height: 88,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.photo_camera_outlined,
              size: 36,
              color: AppColors.onSurfaceMuted,
            ),
          ),
        );
      } catch (_) {
        return const Icon(
          Icons.photo_camera_outlined,
          size: 36,
          color: AppColors.onSurfaceMuted,
        );
      }
    }

    // Si es una URL o ruta local
    return ClipOval(
      child: Image.network(
        logoPath,
        width: 88,
        height: 88,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(
          Icons.photo_camera_outlined,
          size: 36,
          color: AppColors.onSurfaceMuted,
        ),
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
}
