import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/widgets/app_widgets.dart';
import 'offline_operation_queue.dart';

class OfflineQueueBanner extends StatelessWidget {
  const OfflineQueueBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final queue = OfflineOperationQueue.instance;
    return AnimatedBuilder(
      animation: queue,
      builder: (context, _) {
        final state = queue.state;
        if (state == OfflineQueueState.synced ||
            state == OfflineQueueState.queued ||
            state == OfflineQueueState.syncing) {
          return const SizedBox.shrink();
        }
        final count = queue.operations.length;
        final text = switch (state) {
          OfflineQueueState.offline =>
            count == 0
                ? 'Hors ligne · les données nécessitent une connexion.'
                : 'Hors ligne · $count opération${count == 1 ? '' : 's'} en attente.',
          OfflineQueueState.queued =>
            '$count opération${count == 1 ? '' : 's'} en attente de synchronisation.',
          OfflineQueueState.syncing => 'Synchronisation des opérations…',
          OfflineQueueState.syncError =>
            'Une opération a rencontré un conflit de synchronisation.',
          OfflineQueueState.synced => '',
        };
        return Material(
          color: switch (state) {
            OfflineQueueState.syncError => AppColors.red.withValues(alpha: .18),
            OfflineQueueState.offline => AppColors.amber.withValues(alpha: .17),
            _ => AppColors.primary.withValues(alpha: .16),
          },
          child: InkWell(
            onTap: () => context.push('/offline-sync'),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 9,
                ),
                child: Row(
                  children: [
                    Icon(
                      state == OfflineQueueState.syncError
                          ? Icons.sync_problem_rounded
                          : state == OfflineQueueState.offline
                          ? Icons.cloud_off_rounded
                          : Icons.sync_rounded,
                      size: 17,
                      color: state == OfflineQueueState.syncError
                          ? AppColors.red
                          : AppColors.primaryLight,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        text,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: AppColors.muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class OfflineSyncScreen extends StatelessWidget {
  const OfflineSyncScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final queue = OfflineOperationQueue.instance;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: queue,
          builder: (context, _) {
            final operations = queue.operations;
            return ListView(
              padding: const EdgeInsets.fromLTRB(18, 22, 18, 30),
              children: [
                AppPageHeader(onBack: () => context.pop()),
                const SizedBox(height: 18),
                const AppScreenTitle(
                  title: 'Synchronisation',
                  subtitle: 'État des opérations conservées sur cet appareil',
                ),
                const SizedBox(height: 16),
                AppSurface(
                  borderRadius: 18,
                  child: Text(
                    _stateMessage(queue.state),
                    style: const TextStyle(fontSize: 12, height: 1.4),
                  ),
                ),
                const SizedBox(height: 16),
                if (operations.isEmpty)
                  const AppSurface(
                    borderRadius: 18,
                    child: Text(
                      'Aucune opération en attente.',
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  for (final operation in operations)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: AppSurface(
                        borderRadius: 18,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    operation.label,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Text(
                                  _statusLabel(operation.status),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color:
                                        operation.status ==
                                            OfflineOperationStatus.syncError
                                        ? AppColors.red
                                        : AppColors.amber,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              operation.statusMessage ?? '',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.muted,
                              ),
                            ),
                            if (operation.status ==
                                    OfflineOperationStatus.syncError &&
                                operation.errorCode != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Code renvoyé par le serveur : ${operation.errorCode}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.red,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            if (operation.status ==
                                OfflineOperationStatus.syncError) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                children: [
                                  TextButton(
                                    onPressed: () => _run(
                                      context,
                                      () => queue.retry(operation.id),
                                    ),
                                    child: const Text('Réessayer'),
                                  ),
                                  TextButton(
                                    onPressed: () => _confirmDiscard(
                                      context,
                                      queue,
                                      operation,
                                    ),
                                    child: const Text('Supprimer'),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                if (operations.any(
                  (operation) =>
                      operation.status == OfflineOperationStatus.queued,
                ))
                  FilledButton.icon(
                    onPressed:
                        queue.state == OfflineQueueState.offline ||
                            queue.state == OfflineQueueState.syncing
                        ? null
                        : () => _run(context, queue.synchronize),
                    icon: const Icon(Icons.sync_rounded),
                    label: const Text('Synchroniser maintenant'),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _confirmDiscard(
    BuildContext context,
    OfflineOperationQueue queue,
    OfflineOperationRecord operation,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer l’opération refusée ?'),
        content: const Text(
          'Le serveur a refusé cette opération. Vérifiez son état avant de la supprimer; une opération supprimée ne sera pas renvoyée.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Garder'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await _run(context, () => queue.discardRejected(operation.id));
    }
  }

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } on Exception catch (error, stackTrace) {
      debugPrint('Opération de synchronisation impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('La synchronisation n’a pas abouti. Réessayez.'),
          ),
        );
      }
    }
  }

  String _stateMessage(OfflineQueueState state) => switch (state) {
    OfflineQueueState.offline =>
      'Aucune écriture n’est confirmée hors ligne. Les opérations en attente sont chiffrées sur cet appareil et seront renvoyées avec leur identifiant d’origine.',
    OfflineQueueState.queued =>
      'Les opérations attendent leur tour. Elles seront envoyées dans l’ordre avec leur identifiant idempotent.',
    OfflineQueueState.syncing => 'Synchronisation en cours…',
    OfflineQueueState.syncError =>
      'Une opération a été refusée par le serveur. Les suivantes restent bloquées pour préserver l’ordre; corrigez le conflit en la réessayant ou supprimez-la après vérification.',
    OfflineQueueState.synced => 'Toutes les opérations sont synchronisées.',
  };

  String _statusLabel(OfflineOperationStatus status) => switch (status) {
    OfflineOperationStatus.queued => 'En attente',
    OfflineOperationStatus.syncing => 'En cours',
    OfflineOperationStatus.syncError => 'À vérifier',
  };
}
