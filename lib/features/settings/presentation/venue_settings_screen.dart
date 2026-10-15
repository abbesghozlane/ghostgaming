import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/app_widgets.dart';
import '../data/venue_settings_repository.dart';

class VenueSettingsScreen extends StatefulWidget {
  const VenueSettingsScreen({super.key});

  @override
  State<VenueSettingsScreen> createState() => _VenueSettingsScreenState();
}

class _VenueSettingsScreenState extends State<VenueSettingsScreen> {
  late final VenueSettingsRepository _repository;
  final _name = TextEditingController();
  VenueSettings? _settings;
  String _timeZone = 'Africa/Algiers';
  String? _error;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _repository = VenueSettingsRepository(Supabase.instance.client);
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final settings = await _repository.load();
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _name.text = settings.name;
        _timeZone = settings.timeZone;
        _error = null;
        _loading = false;
      });
    } on VenueSettingsException catch (error) {
      if (mounted) {
        setState(() {
          _error = _errorMessage(error.code);
          _loading = false;
        });
      }
    } on PostgrestException catch (error) {
      debugPrint('Chargement des paramètres impossible : $error');
      if (mounted) {
        setState(() {
          _error = 'Les paramètres de la salle n’ont pas pu être chargés.';
          _loading = false;
        });
      }
    } catch (error, stackTrace) {
      debugPrint('Chargement des paramètres impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _error = 'Les paramètres de la salle n’ont pas pu être chargés.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    final settings = _settings;
    if (_saving || settings == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _repository.save(
        venueId: settings.id,
        name: _name.text,
        timeZone: _timeZone,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Paramètres enregistrés.')),
        );
      }
    } on VenueSettingsException catch (error) {
      if (mounted) setState(() => _error = _errorMessage(error.code));
    } on PostgrestException catch (error) {
      debugPrint('Enregistrement des paramètres impossible : $error');
      if (mounted) {
        setState(() => _error = 'Les paramètres n’ont pas pu être enregistrés.');
      }
    } catch (error, stackTrace) {
      debugPrint('Enregistrement des paramètres impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() => _error = 'Les paramètres n’ont pas pu être enregistrés.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _errorMessage(String code) => switch (code) {
    'FORBIDDEN' => 'Seul le propriétaire peut modifier ces paramètres.',
    'INVALID_VENUE_NAME' => 'Le nom doit contenir de 1 à 100 caractères.',
    'INVALID_TIMEZONE' => 'Choisissez un fuseau horaire disponible.',
    _ => 'Une erreur est survenue.',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 30),
        children: [
          AppScreenTitle(
            title: 'Paramètres de la salle',
            subtitle: 'Profil et horaires locaux',
            trailing: IconButton(
              tooltip: 'Retour',
              onPressed: () => context.go('/home'),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          ),
          if (_loading)
            const SizedBox(
              height: 220,
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            if (_error != null) ...[
              const SizedBox(height: 14),
              AppSurface(
                borderRadius: 16,
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppColors.red),
                ),
              ),
            ],
            const SizedBox(height: 16),
            AppSurface(
              borderRadius: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _name,
                    maxLength: 100,
                    decoration: const InputDecoration(
                      labelText: 'Nom de la salle',
                      prefixIcon: Icon(Icons.storefront_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: _timeZone,
                    decoration: const InputDecoration(
                      labelText: 'Fuseau horaire',
                      prefixIcon: Icon(Icons.schedule_rounded),
                    ),
                    items: [
                      for (final entry
                          in VenueSettingsRepository.timeZones.entries)
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                      if (!VenueSettingsRepository.timeZones.containsKey(
                        _timeZone,
                      ))
                        DropdownMenuItem(
                          value: _timeZone,
                          child: Text(_timeZone),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _timeZone = value);
                    },
                  ),
                  const SizedBox(height: 14),
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Devise',
                      prefixIcon: Icon(Icons.payments_outlined),
                    ),
                    child: Text(_settings?.currency ?? 'DA'),
                  ),
                  const SizedBox(height: 18),
                  AppButton(
                    label: _saving ? 'Enregistrement…' : 'Enregistrer',
                    onPressed: _saving ? () {} : _save,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
