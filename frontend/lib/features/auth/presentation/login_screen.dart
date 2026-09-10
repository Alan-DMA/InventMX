import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import 'login_provider.dart';

/// Pantalla de inicio de sesión de Nexus v3.0
/// CA-03: Muestra campos, botón y estado loading visual
/// CA-04: Sin token → redirige automáticamente al Login
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  static const routePath = '/login';

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    await ref.read(loginProvider.notifier).login(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    // Observa cambios de estado para navegar al éxito o mostrar errores.
    ref.listen<LoginState>(loginProvider, (prev, next) {
      if (next.status == LoginStatus.success) {
        // CA-05: Con token → navega al Dashboard (placeholder)
        context.go('/dashboard');
      }
      if (next.status == LoginStatus.error && next.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
        ref.read(loginProvider.notifier).resetError();
      }
    });

    final loginState = ref.watch(loginProvider);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 32),
                  _buildLogo(),
                  const SizedBox(height: 40),
                  _buildHeader(context),
                  const SizedBox(height: 32),
                  _buildForm(loginState),
                  const SizedBox(height: 24),
                  _buildSubmitButton(loginState),
                  const SizedBox(height: 40),
                  _buildFooter(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------- Secciones ----------

  Widget _buildLogo() {
    return Center(
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: AppColors.emerald.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.emerald.withValues(alpha: 0.3)),
        ),
        child: const Icon(
          Icons.inventory_2_rounded,
          size: 38,
          color: AppColors.emerald,
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Bienvenido a Nexus',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 6),
        Text(
          'Ingresa a tu panel de gestión',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.onSurfaceMuted,
              ),
        ),
      ],
    );
  }

  Widget _buildForm(LoginState state) {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          // Campo correo
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            enabled: !state.isLoading,
            decoration: const InputDecoration(
              labelText: 'Correo electrónico',
              hintText: 'tu@correo.com',
              prefixIcon: Icon(Icons.mail_outline_rounded),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Ingresa tu correo.';
              if (!v.contains('@')) return 'Correo inválido.';
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Campo contraseña
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submit(),
            enabled: !state.isLoading,
            decoration: InputDecoration(
              labelText: 'Contraseña',
              hintText: '••••••••',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Ingresa tu contraseña.';
              if (v.length < 6) return 'Mínimo 6 caracteres.';
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton(LoginState state) {
    return ElevatedButton(
      onPressed: state.isLoading ? null : _submit,
      child: state.isLoading
          ? const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.darkSlate,
              ),
            )
          : const Text('Ingresar'),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Text(
      'Nexus v3.0 · Gestión Comercial para México',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}
