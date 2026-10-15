import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/app_widgets.dart';
import '../data/global_search_repository.dart';

class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  late final GlobalSearchRepository _repository = GlobalSearchRepository(
    Supabase.instance.client,
  );
  final _controller = TextEditingController();
  Timer? _debounce;
  List<GlobalSearchResult> _results = const [];
  bool _loading = false;
  String? _error;
  int _requestVersion = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _requestVersion++;
    if (value.trim().length < 2) {
      setState(() {
        _results = const [];
        _loading = false;
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(value));
  }

  Future<void> _search(String query) async {
    final requestVersion = ++_requestVersion;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await _repository.search(query);
      if (!mounted || requestVersion != _requestVersion) return;
      setState(() => _results = results);
    } on PostgrestException catch (error, stackTrace) {
      debugPrint('Recherche globale refusée par Supabase : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted && requestVersion == _requestVersion) {
        setState(() {
          _results = const [];
          _error =
              'La recherche n’a pas abouti. Vérifiez votre accès et réessayez.';
        });
      }
    } catch (error, stackTrace) {
      debugPrint('Recherche globale impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted && requestVersion == _requestVersion) {
        setState(() {
          _results = const [];
          _error = 'La recherche est momentanément indisponible.';
        });
      }
    } finally {
      if (mounted && requestVersion == _requestVersion) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 28),
        children: [
          AppPageHeader(onBack: () => context.pop()),
          const SizedBox(height: 22),
          const AppScreenTitle(
            title: 'Recherche',
            subtitle: 'Recherchez dans les données de votre salle',
          ),
          const SizedBox(height: 18),
          AppTextField(
            controller: _controller,
            onChanged: _onQueryChanged,
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Effacer la recherche',
                    onPressed: () {
                      _controller.clear();
                      _onQueryChanged('');
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
            hintText: 'Nom, numéro de session ou facture…',
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: AppSurface(
                borderRadius: 16,
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppColors.red),
                ),
              ),
            )
          else if (_controller.text.trim().length < 2)
            const Padding(
              padding: EdgeInsets.only(top: 22),
              child: Text(
                'Saisissez au moins deux caractères pour lancer la recherche.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted),
              ),
            )
          else if (_results.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 22),
              child: Text(
                'Aucun résultat.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted),
              ),
            )
          else
            ..._results.map(
              (result) => Padding(
                padding: const EdgeInsets.only(top: 9),
                child: AppSurface(
                  borderRadius: 16,
                  onTap: () => context.go(result.route),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.manage_search_rounded,
                        color: AppColors.primaryLight,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              result.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              result.subtitle,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        result.section,
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.muted,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.muted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
