import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/app_widgets.dart';
import '../../../core/supabase/supabase_config.dart';
import '../data/supabase_auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _formError;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final email = _emailController.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email) ||
        _passwordController.text.isEmpty) {
      setState(
        () => _formError =
            'Saisissez une adresse e-mail et un mot de passe valides.',
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _formError = null;
    });
    try {
      await SupabaseAuthService.instance.signIn(
        email: email,
        password: _passwordController.text,
      );
      if (mounted) context.go('/home');
    } on AuthFlowException catch (error) {
      if (mounted) setState(() => _formError = error.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _formError = 'Saisissez d’abord votre adresse e-mail.');
      return;
    }
    try {
      await SupabaseAuthService.instance.sendPasswordReset(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Consultez votre boîte e-mail pour réinitialiser le mot de passe.',
            ),
          ),
        );
      }
    } on AuthFlowException catch (error) {
      if (mounted) setState(() => _formError = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 190,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  gradient: const RadialGradient(
                    center: Alignment(0, -0.7),
                    radius: 1.2,
                    colors: [Color(0x663A1A82), Color(0x00090915)],
                  ),
                ),
                child: const Center(child: AppBrandLogo(fontSize: 26)),
              ),
              Text(
                'Connexion',
                style: Theme.of(
                  context,
                ).textTheme.displayLarge?.copyWith(fontSize: 24),
              ),
              const SizedBox(height: 4),
              const Text(
                'Bon retour ! Connectez-vous à votre compte',
                style: TextStyle(fontSize: 13, color: AppColors.muted),
              ),
              if (!SupabaseConfig.isConfigured) ...[
                const SizedBox(height: 16),
                const AppSurface(
                  borderRadius: 16,
                  child: Text(
                    'Le serveur Supabase n’est pas configuré. '
                    'Lancez l’application avec SUPABASE_URL et SUPABASE_ANON_KEY.',
                    style: TextStyle(fontSize: 12, color: AppColors.amber),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              AppTextField(
                hintText: 'Adresse e-mail',
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                prefixIcon: const Icon(Icons.mail_outline_rounded),
              ),
              const SizedBox(height: 14),
              AppTextField(
                hintText: 'Mot de passe',
                controller: _passwordController,
                obscureText: true,
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: const Icon(Icons.visibility_off_outlined),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _resetPassword,
                  child: const Text(
                    'Mot de passe oublié ?',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.pink,
                    ),
                  ),
                ),
              ),
              if (_formError != null) ...[
                const SizedBox(height: 4),
                Text(
                  _formError!,
                  style: const TextStyle(color: AppColors.red, fontSize: 13),
                ),
              ],
              const SizedBox(height: 10),
              AppButton(
                label: _isLoading ? 'Connexion en cours…' : 'Se connecter',
                onPressed: _isLoading ? () {} : _signIn,
              ),
              const SizedBox(height: 24),
              Center(
                child: GestureDetector(
                  onTap: () => context.go('/signup'),
                  child: RichText(
                    text: const TextSpan(
                      text: 'Pas encore de compte ? ',
                      style: TextStyle(fontSize: 13, color: AppColors.muted),
                      children: [
                        TextSpan(
                          text: 'Créer mon compte',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.pink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: TextButton(
                  onPressed: SupabaseConfig.isConfigured
                      ? () => context.go('/staff/invite')
                      : null,
                  child: const Text('Rejoindre une équipe avec un code'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
