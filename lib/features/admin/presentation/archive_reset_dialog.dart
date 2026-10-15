import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/app_widgets.dart';
import '../data/archive_repository.dart';

class ArchiveResetDialog extends StatefulWidget {
  const ArchiveResetDialog({super.key});

  @override
  State<ArchiveResetDialog> createState() => _ArchiveResetDialogState();
}

class _ArchiveResetDialogState extends State<ArchiveResetDialog> {
  late final ArchiveRepository _repository;
  final _confirmController = TextEditingController();
  bool _working = false;
  bool _archived = false;
  String? _jsonArchive;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repository = ArchiveRepository(Supabase.instance.client);
    _confirmController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _generateArchive() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final json = await _repository.exportArchiveJson();
      if (!mounted) return;
      setState(() {
        _jsonArchive = json;
        _archived = true;
      });
      await Clipboard.setData(ClipboardData(text: json));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Archive JSON générée et copiée dans le presse-papiers !'),
            backgroundColor: AppColors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Impossible de générer l’archive : $e');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _executeReset() async {
    if (_confirmController.text.trim().toUpperCase() != 'RESET') return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await _repository.resetVenueData();
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Historique purgé avec succès. Vos données essentielles ont été conservées !'),
          backgroundColor: AppColors.green,
        ),
      );
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(() => _error = 'Erreur lors du nettoyage : ${e.message}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Erreur lors du nettoyage : $e');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canReset = _archived && _confirmController.text.trim().toUpperCase() == 'RESET';

    return AlertDialog(
      backgroundColor: const Color(0xFF121226),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: const BorderSide(color: Color(0xFF26264F), width: 1.5),
      ),
      title: Row(
        children: const [
          Icon(Icons.archive_rounded, color: AppColors.pink, size: 24),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Archiver & Purger les données',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cette opération génère un fichier JSON d’archive complète de votre historique (sessions, ventes, dépenses, ورديات) puis nettoie la base de données.',
              style: TextStyle(fontSize: 12, height: 1.45, color: AppColors.muted),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.green.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    ' Données conservées (Non supprimées) :',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.green),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '• Comptes utilisateurs, clients & soldes محفظة\n'
                    '• Postes / Consoles & tarifs\n'
                    '• Catalogue jeux & produits (stock actuel conservé)\n'
                    '• Plans, formules & remises',
                    style: TextStyle(fontSize: 11, height: 1.4, color: Colors.white70),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            // Step 1: Export Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _working ? null : _generateArchive,
                icon: Icon(
                  _archived ? Icons.check_circle_rounded : Icons.download_rounded,
                  color: _archived ? AppColors.green : AppColors.pink,
                ),
                label: Text(
                  _archived ? 'Archive JSON générée' : '1. Télécharger l’archive JSON',
                  style: TextStyle(
                    color: _archived ? AppColors.green : Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            if (_jsonArchive != null) ...[
              const SizedBox(height: 8),
              const Text(
                'L’archive JSON a été copiée dans votre presse-papiers. Vous pouvez la coller et la sauvegarder dans un fichier.',
                style: TextStyle(fontSize: 11, color: AppColors.green),
              ),
            ],
            const SizedBox(height: 18),
            // Step 2: Confirmation input
            const Text(
              '2. Saisissez "RESET" pour confirmer la purge :',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _confirmController,
              enabled: _archived && !_working,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: _archived ? 'Saisissez RESET' : 'Générez d’abord l’archive',
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
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
      actions: [
        TextButton(
          onPressed: _working ? null : () => Navigator.pop(context, false),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          onPressed: (_working || !canReset) ? null : _executeReset,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.red,
            disabledBackgroundColor: Colors.white10,
          ),
          icon: _working
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.delete_forever_rounded, size: 18),
          label: const Text('Purger l’historique'),
        ),
      ],
    );
  }
}
