import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/app_widgets.dart';
import '../data/supabase_auth_service.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _fullNameController = TextEditingController();
  final _venueController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _acceptedTerms = false;
  bool _isLoading = false;
  String? _formError;

  @override
  void dispose() {
    _fullNameController.dispose();
    _venueController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    final email = _emailController.text.trim();
    final validEmail = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);

    if (_fullNameController.text.trim().isEmpty ||
        _venueController.text.trim().isEmpty ||
        !validEmail ||
        _passwordController.text.length < 8 ||
        _confirmPasswordController.text != _passwordController.text ||
        !_acceptedTerms) {
      setState(() {
        _formError =
            'Saisissez toutes les informations nécessaires, y compris le nom de votre salle de jeu, une adresse e-mail/Gmail valide et un mot de passe d’au moins 8 caractères.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _formError = null;
    });
    try {
      final isReady = await SupabaseAuthService.instance.signUp(
        fullName: _fullNameController.text,
        venueName: _venueController.text,
        email: email,
        phone: '',
        password: _passwordController.text,
      );
      if (!mounted) return;
      if (isReady) {
        context.go('/home');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Compte client créé et associé à votre salle avec succès ! Connectez-vous avec votre e-mail et mot de passe.',
            ),
          ),
        );
        context.go('/login');
      }
    } on AuthFlowException catch (error) {
      if (mounted) setState(() => _formError = error.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  AppSurface(
                    borderRadius: 15,
                    padding: const EdgeInsets.all(10),
                    onTap: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go('/login');
                      }
                    },
                    child: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 18,
                    ),
                  ),
                  const AppBrandLogo(
                    title: 'GHOST',
                    subtitle: 'ESPACE CLIENT',
                    fontSize: 15,
                  ),
                  const SizedBox(width: 42),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Inscription Client',
                style: Theme.of(
                  context,
                ).textTheme.displayLarge?.copyWith(fontSize: 24),
              ),
              const SizedBox(height: 4),
              const Text(
                'Créez votre compte client et associez-le à votre salle de jeu',
                style: TextStyle(fontSize: 13, color: AppColors.muted),
              ),
              const SizedBox(height: 20),

              AppTextField(
                hintText: 'Nom et prénom',
                controller: _fullNameController,
                prefixIcon: const Icon(Icons.person_outline_rounded),
              ),
              const SizedBox(height: 12),
              AppTextField(
                hintText: 'Nom de votre salle de jeu (Lieu)',
                controller: _venueController,
                prefixIcon: const Icon(Icons.store_rounded),
              ),
              const SizedBox(height: 12),
              AppTextField(
                hintText: 'Adresse Gmail / E-mail',
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                prefixIcon: const Icon(Icons.mail_outline_rounded),
              ),
              const SizedBox(height: 12),
              AppTextField(
                hintText: 'Mot de passe (8 caractères minimum)',
                controller: _passwordController,
                obscureText: true,
                prefixIcon: const Icon(Icons.lock_outline_rounded),
              ),
              const SizedBox(height: 12),
              AppTextField(
                hintText: 'Confirmer le mot de passe',
                controller: _confirmPasswordController,
                obscureText: true,
                prefixIcon: const Icon(Icons.lock_outline_rounded),
              ),
              const SizedBox(height: 14),
              CheckboxListTile(
                value: _acceptedTerms,
                onChanged: (value) =>
                    setState(() => _acceptedTerms = value ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'J’accepte les Conditions Générales et la Politique de Confidentialité.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.muted,
                    height: 1.4,
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
              const SizedBox(height: 14),
              AppButton(
                label: _isLoading ? 'Création du compte…' : 'Créer mon compte client',
                onPressed: _isLoading ? () {} : _signUp,
              ),
              const SizedBox(height: 20),
              Center(
                child: GestureDetector(
                  onTap: () => context.go('/login'),
                  child: RichText(
                    text: const TextSpan(
                      text: 'Vous avez déjà un compte ? ',
                      style: TextStyle(fontSize: 13, color: AppColors.muted),
                      children: [
                        TextSpan(
                          text: 'Se connecter',
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
            ],
          ),
        ),
      ),
    );
  }
}
