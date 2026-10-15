import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/app_widgets.dart';
import '../data/customer_repository.dart';

class CustomerLinkScreen extends StatefulWidget {
  const CustomerLinkScreen({required this.qrToken, super.key});

  final String? qrToken;

  @override
  State<CustomerLinkScreen> createState() => _CustomerLinkScreenState();
}

class _CustomerLinkScreenState extends State<CustomerLinkScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  late final CustomerRepository _repository;
  bool _codeSent = false;
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final client = Supabase.instance.client;
    _repository = CustomerRepository(client);
    _phoneController.text = client.auth.currentUser?.phone ?? '';
    final name = client.auth.currentUser?.userMetadata?['full_name'];
    if (name is String) _nameController.text = name;
    if (widget.qrToken case final token? when token.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && client.auth.currentUser != null) {
          _linkPost(token);
        }
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    final phone = _phoneController.text.trim();
    final name = _nameController.text.trim();
    if (name.length < 2 || !RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(phone)) {
      setState(
        () => _error =
            'Saisissez votre nom et un numéro au format international, par exemple +213XXXXXXXXX.',
      );
      return;
    }
    await _run(() async {
      await _repository.requestPhoneCode(phone: phone, fullName: name);
      if (mounted) setState(() => _codeSent = true);
    });
  }

  Future<void> _verifyCode() async {
    final phone = _phoneController.text.trim();
    final code = _codeController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'Saisissez le code à six chiffres reçu par SMS.');
      return;
    }
    await _run(() async {
      await _repository.verifyPhoneCode(
        phone: phone,
        code: code,
        fullName: _nameController.text.trim(),
      );
      final token = widget.qrToken;
      if (token != null && token.isNotEmpty) {
        await _repository.linkToPost(token);
      }
      if (mounted) context.go('/customer/home');
    });
  }

  Future<void> _linkPost(String token) async {
    await _run(() async {
      await _repository.linkToPost(token);
      if (mounted) context.go('/customer/home');
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await action();
    } on CustomerFlowException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = _authMessage(error));
    } on PostgrestException catch (error) {
      if (mounted) setState(() => _error = _rpcMessage(error.message));
    } catch (error, stackTrace) {
      debugPrint('Liaison du compte client impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(
          () => _error =
              'La vérification a échoué. Vérifiez votre connexion et réessayez.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String _authMessage(AuthException error) {
    final message = error.message.toLowerCase();
    if (message.contains('rate limit') || message.contains('too many')) {
      return 'Trop de demandes. Attendez quelques instants avant de réessayer.';
    }
    if (message.contains('expired') || message.contains('invalid')) {
      return 'Le code est invalide ou expiré. Demandez un nouveau code.';
    }
    return 'Le SMS n’a pas pu être envoyé ou vérifié. Vérifiez le numéro saisi.';
  }

  String _rpcMessage(String message) {
    final code = message.toUpperCase();
    if (code.contains('VERIFIED_PHONE_REQUIRED')) {
      return 'Vérifiez votre numéro de téléphone avant de scanner le QR.';
    }
    if (code.contains('POST_QR_NOT_FOUND') ||
        code.contains('POST_QR_INVALID')) {
      return 'Ce QR ne correspond pas à un poste reconnu.';
    }
    if (code.contains('POST_UNAVAILABLE')) {
      return 'Ce poste est temporairement indisponible.';
    }
    if (code.contains('CUSTOMER_ACCOUNT_ALREADY_LINKED')) {
      return 'Un autre compte client utilise déjà ce numéro pour cette salle.';
    }
    if (code.contains('VENUE_MEMBER_ROLE_CONFLICT')) {
      return 'Ce compte est déjà associé à la salle avec un autre rôle.';
    }
    if (code.contains('VENUE_ACCESS_REVOKED')) {
      return 'L’accès à cette salle a été désactivé. Contactez son équipe.';
    }
    return 'La liaison au poste a échoué. Vérifiez le QR et réessayez.';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        children: [
          AppPageHeader(onBack: () => context.pop()),
          const SizedBox(height: 26),
          const AppScreenTitle(
            title: 'Espace client',
            subtitle: 'Vérifiez votre numéro pour rejoindre votre salle.',
          ),
          const SizedBox(height: 22),
          AppSurface(
            borderRadius: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.qr_code_scanner_rounded,
                  size: 30,
                  color: AppColors.pink,
                ),
                const SizedBox(height: 12),
                Text(
                  widget.qrToken == null
                      ? 'Scannez le QR d’un poste pour lier votre compte.'
                      : 'Votre numéro vérifié autorise la liaison au poste scanné.',
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
                if (widget.qrToken == null) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _working
                        ? null
                        : () => context.push('/customer/scan'),
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    label: const Text('Scanner le QR du poste'),
                  ),
                ],
                const SizedBox(height: 18),
                if (!_codeSent) ...[
                  AppTextField(
                    hintText: 'Nom et prénom',
                    controller: _nameController,
                    prefixIcon: const Icon(Icons.person_outline_rounded),
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    hintText: 'Téléphone (+213...)',
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    prefixIcon: const Icon(Icons.phone_outlined),
                  ),
                  const SizedBox(height: 16),
                  AppButton(
                    label: _working ? 'Envoi du code…' : 'Recevoir un code SMS',
                    onPressed: _working ? () {} : _requestCode,
                  ),
                ] else ...[
                  Text(
                    'Un code de vérification a été envoyé au ${_phoneController.text.trim()}.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    hintText: 'Code à 6 chiffres',
                    controller: _codeController,
                    keyboardType: TextInputType.number,
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                  ),
                  const SizedBox(height: 16),
                  AppButton(
                    label: _working ? 'Vérification…' : 'Vérifier et continuer',
                    onPressed: _working ? () {} : _verifyCode,
                  ),
                  TextButton(
                    onPressed: _working
                        ? null
                        : () => setState(() {
                            _codeSent = false;
                            _codeController.clear();
                          }),
                    child: const Text('Modifier le numéro'),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(color: AppColors.red, fontSize: 12),
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
