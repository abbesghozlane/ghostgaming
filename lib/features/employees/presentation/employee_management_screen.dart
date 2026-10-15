import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/app_bottom_nav.dart';
import '../../../app/widgets/app_widgets.dart';
import '../data/employee_repository.dart';

class EmployeeManagementScreen extends StatefulWidget {
  const EmployeeManagementScreen({super.key});

  @override
  State<EmployeeManagementScreen> createState() =>
      _EmployeeManagementScreenState();
}

class _EmployeeManagementScreenState extends State<EmployeeManagementScreen> {
  late final EmployeeRepository _repository;
  EmployeeManagementSnapshot? _snapshot;
  Object? _error;
  bool _loading = true;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _repository = EmployeeRepository(Supabase.instance.client);
    _load();
  }

  Future<void> _load() async {
    try {
      final snapshot = await _repository.load();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _error = null;
        _loading = false;
      });
    } on EmployeeManagementException catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    } on PostgrestException catch (error) {
      if (mounted) {
        setState(() {
          _error = _friendlyError(error.message);
          _loading = false;
        });
      }
    } catch (error, stackTrace) {
      debugPrint('Chargement des employés impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _error = 'La liste des employés n’a pas pu être chargée.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _invite() async {
    final invitation = await showDialog<_InvitationForm>(
      context: context,
      builder: (context) => const _InvitationDialog(),
    );
    if (invitation == null) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final result = await _repository.createInvitation(
        email: invitation.email,
        permissions: invitation.permissions,
      );
      if (!mounted) return;
      await _showInvitationCode(
        result['token'] as String,
        result['email'] as String,
      );
      await _load();
    } on PostgrestException catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error.message));
    } catch (error, stackTrace) {
      debugPrint('Création de l’invitation impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) setState(() => _error = 'L’invitation n’a pas été créée.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _showInvitationCode(String token, String email) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Invitation créée'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Envoyez ce code à $email. Il expire dans sept jours.'),
            const SizedBox(height: 14),
            SelectableText(
              token,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
                color: AppColors.pink,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Le destinataire ouvre « Rejoindre une équipe » depuis la connexion, crée un compte avec cette adresse, confirme son e-mail puis saisit le code.',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: token));
              if (context.mounted) Navigator.pop(context);
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copier le code'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  Future<void> _editPermissions(EmployeeMember employee) async {
    final permissions = await showDialog<Map<String, bool>>(
      context: context,
      builder: (context) =>
          _PermissionsDialog(initialPermissions: employee.permissions),
    );
    if (permissions == null) return;
    await _perform(
      () => _repository.updatePermissions(employee.userId, permissions),
    );
  }

  Future<void> _setActive(EmployeeMember employee) async {
    final activate = !employee.isActive;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          activate ? 'Réactiver le compte ?' : 'Désactiver le compte ?',
        ),
        content: Text(
          activate
              ? '${employee.email} retrouvera l’accès à cette salle.'
              : '${employee.email} perdra immédiatement l’accès à cette salle.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(activate ? 'Réactiver' : 'Désactiver'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _perform(() => _repository.setActive(employee.userId, activate));
  }

  Future<void> _cancelInvitation(EmployeeInvitation invitation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Annuler l’invitation ?'),
        content: Text(
          'Le code envoyé à ${invitation.email} ne fonctionnera plus.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Garder'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Annuler l’invitation'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _perform(() => _repository.cancelInvitation(invitation.id));
  }

  Future<void> _perform(Future<void> Function() action) async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await action();
      await _load();
    } on PostgrestException catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error.message));
    } catch (error, stackTrace) {
      debugPrint('Modification des employés impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) setState(() => _error = 'La modification a échoué.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String _friendlyError(String message) {
    final code = message.toUpperCase();
    if (code.contains('FORBIDDEN') || code.contains('42501')) {
      return 'Seul le propriétaire peut gérer les employés.';
    }
    if (code.contains('INVALID_EMAIL')) {
      return 'Saisissez une adresse e-mail valide.';
    }
    if (code.contains('INVALID_PERMISSIONS')) {
      return 'Les autorisations choisies ne sont pas valides.';
    }
    if (code.contains('MEMBER_ALREADY_EXISTS')) {
      return 'Cette adresse appartient déjà à un membre de la salle. Réactivez son compte depuis la liste des employés.';
    }
    if (code.contains('EMPLOYEE_NOT_FOUND')) {
      return 'Cet employé n’existe plus dans votre équipe.';
    }
    return 'Une erreur est survenue. Réessayez.';
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 20, 18, 28),
                  children: [
                    AppPageHeader(
                      onBack: () => context.go('/admin'),
                      trailing: IconButton(
                        tooltip: 'Inviter un employé',
                        onPressed: _working ? null : _invite,
                        icon: const Icon(Icons.person_add_alt_1_rounded),
                      ),
                    ),
                    const SizedBox(height: 18),
                    AppScreenTitle(
                      title: 'Équipe',
                      subtitle:
                          snapshot?.venue.name ??
                          'Employés, invitations et autorisations',
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      _Notice(
                        message: _error is EmployeeManagementException
                            ? (_error as EmployeeManagementException).message
                            : _error.toString(),
                      ),
                    ],
                    if (_loading)
                      const SizedBox(
                        height: 180,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (snapshot == null)
                      const _Notice(
                        message: 'Les données de l’équipe sont indisponibles.',
                      )
                    else ...[
                      const SizedBox(height: 16),
                      _SectionHeading(
                        title: 'Employés',
                        count: snapshot.employees.length,
                      ),
                      const SizedBox(height: 10),
                      if (snapshot.employees.isEmpty)
                        const _Notice(
                          message:
                              'Aucun employé. Créez une invitation pour commencer.',
                        )
                      else
                        for (final employee in snapshot.employees)
                          _EmployeeCard(
                            employee: employee,
                            busy: _working,
                            onEdit: () => _editPermissions(employee),
                            onToggle: () => _setActive(employee),
                          ),
                      const SizedBox(height: 20),
                      _SectionHeading(
                        title: 'Invitations en attente',
                        count: snapshot.invitations.length,
                      ),
                      const SizedBox(height: 10),
                      if (snapshot.invitations.isEmpty)
                        const _Notice(message: 'Aucune invitation en attente.')
                      else
                        for (final invitation in snapshot.invitations)
                          _InvitationCard(
                            invitation: invitation,
                            busy: _working,
                            onCancel: () => _cancelInvitation(invitation),
                          ),
                    ],
                  ],
                ),
              ),
            ),
            const AppBottomNav(currentIndex: 4, isStaff: true),
          ],
        ),
      ),
    );
  }
}

class _InvitationForm {
  const _InvitationForm(this.email, this.permissions);

  final String email;
  final Map<String, bool> permissions;
}

class _InvitationDialog extends StatefulWidget {
  const _InvitationDialog();

  @override
  State<_InvitationDialog> createState() => _InvitationDialogState();
}

class _InvitationDialogState extends State<_InvitationDialog> {
  final _email = TextEditingController();
  final _permissions = <String, bool>{
    for (final key in employeePermissions.keys) key: false,
  };
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Inviter un employé'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Adresse e-mail du compte',
              ),
            ),
            const SizedBox(height: 10),
            for (final entry in employeePermissions.entries)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _permissions[entry.key],
                title: Text(entry.value, style: const TextStyle(fontSize: 13)),
                onChanged: (value) =>
                    setState(() => _permissions[entry.key] = value ?? false),
              ),
            if (_error != null)
              Text(
                _error!,
                style: const TextStyle(color: AppColors.red, fontSize: 12),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(
        onPressed: () {
          final email = _email.text.trim();
          if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
            setState(() => _error = 'Saisissez une adresse e-mail valide.');
            return;
          }
          Navigator.pop(context, _InvitationForm(email, Map.of(_permissions)));
        },
        child: const Text('Créer le code'),
      ),
    ],
  );
}

class _PermissionsDialog extends StatefulWidget {
  const _PermissionsDialog({required this.initialPermissions});

  final Map<String, bool> initialPermissions;

  @override
  State<_PermissionsDialog> createState() => _PermissionsDialogState();
}

class _PermissionsDialogState extends State<_PermissionsDialog> {
  late final _permissions = <String, bool>{
    for (final key in employeePermissions.keys)
      key: widget.initialPermissions[key] ?? false,
  };

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Autorisations employé'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in employeePermissions.entries)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _permissions[entry.key],
              title: Text(entry.value, style: const TextStyle(fontSize: 13)),
              onChanged: (value) =>
                  setState(() => _permissions[entry.key] = value ?? false),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, Map.of(_permissions)),
        child: const Text('Enregistrer'),
      ),
    ],
  );
}

class _EmployeeCard extends StatelessWidget {
  const _EmployeeCard({
    required this.employee,
    required this.busy,
    required this.onEdit,
    required this.onToggle,
  });

  final EmployeeMember employee;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: AppSurface(
      borderRadius: 18,
      padding: const EdgeInsets.all(13),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppColors.primary.withValues(alpha: 0.25),
            child: Text(
              (employee.name ?? employee.email).characters.first.toUpperCase(),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  employee.name ?? employee.email,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${employee.email} · ${employee.role == 'manager' ? 'Manager' : 'Employé'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: AppColors.muted),
                ),
                Text(
                  employee.isActive ? 'Compte actif' : 'Compte désactivé',
                  style: TextStyle(
                    fontSize: 10,
                    color: employee.isActive ? AppColors.green : AppColors.red,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Modifier les autorisations',
            onPressed: busy || employee.role != 'employee' ? null : onEdit,
            icon: const Icon(Icons.tune_rounded),
          ),
          IconButton(
            tooltip: employee.isActive ? 'Désactiver' : 'Réactiver',
            onPressed: busy || employee.role != 'employee' ? null : onToggle,
            icon: Icon(
              employee.isActive
                  ? Icons.person_off_outlined
                  : Icons.person_add_alt_1_rounded,
              color: employee.isActive ? AppColors.red : AppColors.green,
            ),
          ),
        ],
      ),
    ),
  );
}

class _InvitationCard extends StatelessWidget {
  const _InvitationCard({
    required this.invitation,
    required this.busy,
    required this.onCancel,
  });

  final EmployeeInvitation invitation;
  final bool busy;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: AppSurface(
      borderRadius: 18,
      padding: const EdgeInsets.all(13),
      child: Row(
        children: [
          const Icon(Icons.mark_email_unread_outlined, color: AppColors.amber),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invitation.email,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  invitation.expiresAt == null
                      ? 'Invitation créée'
                      : 'Expire le ${DateFormat('dd MMMM yyyy · HH:mm', 'fr_FR').format(invitation.expiresAt!)}',
                  style: const TextStyle(fontSize: 10, color: AppColors.muted),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Annuler l’invitation',
            onPressed: busy ? null : onCancel,
            icon: const Icon(Icons.close_rounded, color: AppColors.red),
          ),
        ],
      ),
    ),
  );
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      Text('$count', style: const TextStyle(color: AppColors.muted)),
    ],
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => AppSurface(
    borderRadius: 16,
    child: Text(
      message,
      style: const TextStyle(fontSize: 12, color: AppColors.muted),
    ),
  );
}
