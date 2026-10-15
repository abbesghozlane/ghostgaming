import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_config.dart';

class AuthFlowException implements Exception {
  const AuthFlowException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SupabaseAuthService {
  SupabaseAuthService._();

  static final SupabaseAuthService instance = SupabaseAuthService._();

  SupabaseClient get _client {
    if (!SupabaseConfig.isConfigured) {
      throw const AuthFlowException(
        'La connexion au serveur n’est pas configurée sur cette installation.',
      );
    }
    return Supabase.instance.client;
  }

  Future<void> signIn({required String email, required String password}) async {
    try {
      await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      await _completeOwnerSetupIfNeeded();
    } on AuthFlowException {
      rethrow;
    } on AuthException catch (error) {
      throw AuthFlowException(_messageForAuthError(error));
    } on PostgrestException catch (error) {
      throw AuthFlowException(_messageForPostgresError(error.message));
    }
  }

  Future<bool> signUp({
    required String fullName,
    required String venueName,
    required String email,
    required String phone,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signUp(
        email: email.trim(),
        password: password,
        data: {
          'full_name': fullName.trim(),
          'venue_name': venueName.trim(),
          'phone': phone.trim(),
        },
      );
      if (response.session == null) return false;
      await _client.rpc('setup_customer_venue');
      return true;
    } on AuthFlowException {
      rethrow;
    } on AuthException catch (error) {
      throw AuthFlowException(_messageForAuthError(error));
    } on PostgrestException catch (error) {
      throw AuthFlowException(_messageForPostgresError(error.message));
    }
  }

  Future<void> sendPasswordReset(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(email.trim());
    } on AuthFlowException {
      rethrow;
    } on AuthException {
      throw const AuthFlowException(
        'Le lien de réinitialisation n’a pas pu être envoyé. Vérifiez votre adresse.',
      );
    }
  }

  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } on AuthFlowException {
      rethrow;
    } on AuthException {
      throw const AuthFlowException('La déconnexion a échoué. Réessayez.');
    }
  }

  Future<void> _completeOwnerSetupIfNeeded() async {
    final user = _client.auth.currentUser;
    final metadata = user?.userMetadata;
    if (metadata == null || metadata['venue_name'] == null) return;
    try {
      await _client.rpc('setup_customer_venue');
    } catch (error) {
      debugPrint('Configuration du compte client impossible : $error');
    }
  }

  String _messageForAuthError(AuthException error) {
    final message = error.message.toLowerCase();
    if (message.contains('invalid login credentials')) {
      return 'Adresse e-mail ou mot de passe incorrect.';
    }
    if (message.contains('email not confirmed') ||
        message.contains('email_not_confirmed')) {
      return 'Confirmez votre adresse e-mail avant de vous connecter.';
    }
    if (message.contains('rate limit') ||
        message.contains('too many requests')) {
      return 'Trop de tentatives. Attendez quelques minutes avant de réessayer.';
    }
    if (message.contains('already registered') ||
        message.contains('already exists')) {
      return 'Cette adresse e-mail possède déjà un compte.';
    }
    if (message.contains('password')) {
      return 'Le mot de passe ne respecte pas les exigences de sécurité.';
    }
    if (message.contains('email')) {
      return 'Vérifiez le format de votre adresse e-mail.';
    }
    return 'Échec de l’authentification : ${error.message}';
  }

  String _messageForPostgresError(String message) {
    final code = message.toUpperCase();
    if (code.contains('VENUE_NOT_FOUND')) {
      return 'Aucune salle de jeu ne porte ce nom. Vérifiez le nom exact auprès du propriétaire de la salle.';
    }
    if (code.contains('VENUE_NAME_REQUIRED')) {
      return 'Le nom de la salle de jeu est obligatoire.';
    }
    if (code.contains('CUSTOMER_ACCOUNT_ALREADY_LINKED')) {
      return 'Ce compte client est déjà associé à cette salle.';
    }
    return 'Configuration de la salle impossible : $message';
  }
}
