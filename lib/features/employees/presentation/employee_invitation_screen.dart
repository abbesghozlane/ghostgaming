import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/app_widgets.dart';
import '../data/employee_repository.dart';

class EmployeeInvitationScreen extends StatefulWidget {
  const EmployeeInvitationScreen({required this.token, super.key});

  final String? token;

  @override
  State<EmployeeInvitationScreen> createState() =>
      _EmployeeInvitationScreenState();
}

class _EmployeeInvitationScreenState extends State<EmployeeInvitationScreen> {
  final _token = TextEditingController();
  final _email = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();
  late final EmployeeRepository _repository;
  bool _hasAccount = false;
  bool _working = false;
  bool _emailConfirmationRequired = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repository = EmployeeRepository(Supabase.instance.client);
    _token.text = widget.token ?? '';
    _email.text = Supabase.instance.client.auth.currentUser?.email ?? '';
    _hasAccount = Supabase.instance.client.auth.currentSession != null;
    if (_hasAccount && _token.text.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _accept());
    }
  }

  @override
  void dispose() {
    _token.dispose();
    _email.dispose();
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _createAccount() async {
    final email = _email.text.trim();
    final name = _name.text.trim();
    final password = _password.text;
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email) ||
        name.length < 2 ||
        password.length < 8 ||
        _token.text.trim().isEmpty) {
      setState(
        () => _error =
            'Saisissez le code, votre nom, une adresse e-mail valide et un mot de passe d’au moins 8 caractères.',
      );
      return;
    }
    var hasSession = false;
    await _run(() async {
      hasSession = await _repository.signUpInvitedEmployee(
        email: email,
        password: password,
        fullName: name,
      );
      if (!hasSession) {
        if (mounted) {
          setState(() {
            _emailConfirmationRequired = true;
            _hasAccount = true;
          });
        }
        return;
      }
    });
    if (hasSession && mounted) await _accept();
  }

  Future<void> _signInAndAccept() async {
    if (_token.text.trim().isEmpty ||
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_email.text.trim()) ||
        _password.text.isEmpty) {
      setState(
        () => _error =
            'Saisissez l’adresse e-mail invitée, le mot de passe et le code d’invitation.',
      );
      return;
    }
    await _run(() async {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
      await _accept();
    });
  }

  Future<void> _accept() async {
    final token = _token.text.trim();
    if (token.isEmpty) {
      if (mounted) setState(() => _error = 'Saisissez le code d’invitation.');
      return;
    }
    await _run(() async {
      await _repository.acceptInvitation(token);
      if (mounted) context.go('/home');
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await action();
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = _authError(error));
    } on PostgrestException catch (error) {
      if (mounted) setState(() => _error = _invitationError(error.message));
    } catch (error, stackTrace) {
      debugPrint('Acceptation de l’invitation impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() => _error = 'L’opération a échoué. Réessayez.');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String _authError(AuthException error) {
    final message = error.message.toLowerCase();
    if (message.contains('already registered') ||
        message.contains('already exists')) {
      return 'Cette adresse possède déjà un compte. Choisissez « J’ai déjà un compte ».';
    }
    if (message.contains('email not confirmed') ||
        message.contains('email_not_confirmed')) {
      return 'Confirmez votre adresse e-mail, puis connectez-vous avec le même code.';
    }
    if (message.contains('invalid login credentials')) {
      return 'Adresse e-mail ou mot de passe incorrect.';
    }
    if (message.contains('rate limit')) {
      return 'Trop de tentatives. Attendez quelques instants avant de réessayer.';
    }
    return 'L’authentification a échoué. Vérifiez les informations saisies.';
  }

  String _invitationError(String message) {
    final code = message.toUpperCase();
    if (code.contains('INVITATION_INVALID')) {
      return 'Le code d’invitation est incorrect.';
    }
    if (code.contains('INVITATION_EMAIL_MISMATCH')) {
      return 'Connectez-vous avec l’adresse e-mail à laquelle l’invitation a été envoyée.';
    }
    if (code.contains('CONFIRMED_EMAIL_REQUIRED')) {
      return 'Confirmez votre adresse e-mail avant d’accepter l’invitation.';
    }
    if (code.contains('INVITATION_EXPIRED')) {
      return 'Cette invitation a expiré. Demandez un nouveau code au propriétaire.';
    }
    if (code.contains('INVITATION_CANCELLED')) {
      return 'Cette invitation a été annulée par le propriétaire.';
    }
    if (code.contains('INVITATION_ALREADY_USED') ||
        code.contains('MEMBER_ALREADY_EXISTS')) {
      return 'Cette invitation a déjà été utilisée ou ce compte appartient déjà à la salle.';
    }
    return 'L’invitation n’a pas pu être acceptée. Vérifiez le code et votre connexion.';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        children: [
          AppPageHeader(onBack: () => context.go('/login')),
          const SizedBox(height: 24),
          const AppScreenTitle(
            title: 'Rejoindre une équipe',
            subtitle:
                'Utilisez le code transmis par le propriétaire de la salle.',
          ),
          const SizedBox(height: 18),
          AppSurface(
            borderRadius: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _token,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Code d’invitation',
                    suffixIcon: IconButton(
                      tooltip: 'Coller le code',
                      onPressed: () async {
                        final data = await Clipboard.getData('text/plain');
                        if (data?.text != null) {
                          _token.text = data!.text!.trim();
                        }
                      },
                      icon: const Icon(Icons.content_paste_rounded),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (!_hasAccount) ...[
                  TextField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Nom complet'),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Adresse e-mail invitée',
                  ),
                ),
                if (!_emailConfirmationRequired) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: _hasAccount
                          ? 'Mot de passe'
                          : 'Créer un mot de passe (8 caractères minimum)',
                    ),
                  ),
                ],
                if (_emailConfirmationRequired) ...[
                  const SizedBox(height: 14),
                  const Text(
                    'Un e-mail de confirmation a été envoyé. Après l’avoir confirmé, saisissez votre mot de passe et acceptez le code.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      color: AppColors.amber,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Mot de passe confirmé',
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(color: AppColors.red, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 16),
                AppButton(
                  label: _working
                      ? 'Traitement…'
                      : _hasAccount
                      ? 'Se connecter et rejoindre'
                      : 'Créer le compte et rejoindre',
                  onPressed: _working
                      ? () {}
                      : _hasAccount
                      ? _signInAndAccept
                      : _createAccount,
                ),
                if (!_hasAccount) ...[
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: _working
                          ? null
                          : () => setState(() {
                              _hasAccount = true;
                              _error = null;
                            }),
                      child: const Text('J’ai déjà un compte'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
