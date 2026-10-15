import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/app_bottom_nav.dart';
import '../../../app/widgets/app_widgets.dart';
import '../../../app/widgets/responsive_scaffold.dart';
import '../../../core/data/current_role_cache.dart';
import '../../../core/data/venue_repository.dart';
import '../../../core/storage/catalog_image_storage.dart';
import '../data/game_catalog_repository.dart';
import '../domain/game_classification_service.dart';
import '../domain/game_timing_policy.dart';

class GameStoreScreen extends StatefulWidget {
  const GameStoreScreen({super.key});

  @override
  State<GameStoreScreen> createState() => _GameStoreScreenState();
}

class _GameStoreScreenState extends State<GameStoreScreen> {
  final _repository = GameCatalogRepository(Supabase.instance.client);
  final _searchController = TextEditingController();
  final _searchFocus = ValueNotifier<String>('');
  GameCatalogSnapshot? _snapshot;
  RealtimeChannel? _channel;
  Timer? _refreshDebounce;
  int _selectedChip = 0;
  bool _loading = true;
  bool _working = false;
  String? _error;
  final List<String> _chips = ['Tous', 'Matchs', 'Temps'];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(
      () => _searchFocus.value = _searchController.text.trim().toLowerCase(),
    );
    _load();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _refreshDebounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final snapshot = await _repository.load();
      if (!mounted) return;
      final venueChanged = _snapshot?.venue.id != snapshot.venue.id;
      setState(() {
        _snapshot = snapshot;
        _error = null;
      });
      if (venueChanged || _channel == null) {
        _subscribe(snapshot.venue.id);
      }
    } on PostgrestException catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error.message));
    } on VenueRepositoryException catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error.code));
    } catch (error, stackTrace) {
      debugPrint('Chargement du catalogue impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() => _error = 'Le catalogue n’a pas pu être chargé.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _subscribe(String venueId) {
    _channel?.unsubscribe();
    _channel = _repository.subscribe(
      venueId,
      onChange: () {
        _refreshDebounce?.cancel();
        _refreshDebounce = Timer(const Duration(milliseconds: 250), _load);
      },
      onError: () {
        if (mounted && _snapshot == null) {
          setState(
            () => _error =
                'La synchronisation du catalogue est interrompue. Actualisez pour réessayer.',
          );
        }
      },
    );
  }

  Future<void> _editGame([Map<String, dynamic>? game]) async {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    if (!snapshot.venue.canManageCatalog) {
      await CurrentRoleCache.syncRole(Supabase.instance.client);
      final reloaded = await _repository.load();
      if (!mounted) return;
      setState(() => _snapshot = reloaded);
      if (!reloaded.venue.canManageCatalog) {
        setState(() => _error = 'Votre rôle (${reloaded.venue.role}) ne permet pas de modifier le catalogue.');
        return;
      }
    }
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) =>
          _GameFormDialog(existing: game, venueId: _snapshot!.venue.id),
    );
    if (values == null) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await _repository.save(
        venueId: _snapshot!.venue.id,
        values: values,
        gameId: game?['id'] as String?,
      );
      await _load();
    } on PostgrestException catch (error) {
      setState(() => _error = _friendlyError(error.message));
    } catch (error, stackTrace) {
      debugPrint('Enregistrement du jeu impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      setState(() => _error = 'Le jeu n’a pas pu être enregistré.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _setAvailability(Map<String, dynamic> game) async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await _repository.setAvailability(
        game['id'] as String,
        !(game['is_available'] as bool? ?? false),
      );
      await _load();
    } on PostgrestException catch (error) {
      setState(() => _error = _friendlyError(error.message));
    } catch (error, stackTrace) {
      debugPrint('Modification du jeu impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      setState(() => _error = 'La disponibilité du jeu n’a pas été modifiée.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _deleteGame(Map<String, dynamic> game) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer le jeu'),
        content: Text('Voulez-vous vraiment supprimer "${game['name']}" ? Cette action est irréversible.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await _repository.deleteGame(game['id'] as String);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Jeu supprimé avec succès.')),
        );
      }
    } on PostgrestException catch (error) {
      if (mounted) {
        if (error.message.contains('GAME_HAS_HISTORY') || error.code == '23503') {
          await _load();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ce jeu est lié à des sessions passées. Il a été désactivé et masqué au lieu d’être supprimé.'),
            ),
          );
        } else {
          setState(() => _error = _friendlyError(error.message));
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Impossible de supprimer le jeu : $e');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String _friendlyError(String message) {
    final code = message.split(':').first.trim();
    return switch (code) {
      'FORBIDDEN' ||
      '42501' => 'Votre rôle ne permet pas de modifier le catalogue.',
      '23505' => 'Un jeu portant ce nom existe déjà.',
      '23514' => 'Vérifiez le mode de jeu, le prix et la durée du match.',
      'VENUE_NOT_FOUND' => 'Aucune salle n’est associée à votre compte.',
      _ => 'Une erreur est survenue. Vérifiez votre connexion puis réessayez.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final isCustomer = (snapshot?.venue.role ?? CurrentRoleCache.role) == 'customer';
    return ResponsiveScaffold(
      currentIndex: isCustomer ? 2 : 4,
      isStaff: !isCustomer,
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 24),
            children: [
                    AppPageHeader(onBack: () => context.pop()),
                    const SizedBox(height: 18),
                    AppScreenTitle(
                      title: 'Jeux',
                      subtitle: snapshot?.venue.name ?? 'Choisissez votre jeu',
                    ),
                    if (snapshot?.venue.canManageCatalog ?? false) ...[
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _working ? null : () => _editGame(),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Ajouter un jeu'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 15),
                    AppTextField(
                      hintText: 'Rechercher un jeu...',
                      controller: _searchController,
                      prefixIcon: const Icon(Icons.search_rounded),
                    ),
                    const SizedBox(height: 13),
                    SizedBox(
                      height: 40,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _chips.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final selected = _selectedChip == index;
                          return _GameFilterChip(
                            label: _chips[index],
                            selected: selected,
                            onTap: () => setState(() => _selectedChip = index),
                          );
                        },
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      _GameNotice(text: _error!, onRetry: _load),
                    ],
                    if (_loading && snapshot == null)
                      const Padding(
                        padding: EdgeInsets.only(top: 36),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_filteredGames.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 18),
                        child: _GameEmptyState(),
                      )
                    else ...[
                      const SizedBox(height: 14),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isCustomer = (snapshot?.venue.role ?? CurrentRoleCache.role) == 'customer';
                          if (isCustomer && constraints.maxWidth <= 700) {
                            return _CustomerGameCarouselView(games: _filteredGames);
                          }
                          final columns = constraints.maxWidth > 1100
                              ? 4
                              : constraints.maxWidth > 760
                                  ? 3
                                  : 2;
                          return GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _filteredGames.length,
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  crossAxisSpacing: 14,
                                  mainAxisSpacing: 16,
                                  mainAxisExtent: 290,
                                ),
                            itemBuilder: (context, index) {
                              final game = _filteredGames[index];
                              return _GameCard(
                                game: game,
                                canManage:
                                    snapshot?.venue.canManageCatalog ?? false,
                                onEdit: () => _editGame(game),
                                onAvailability: () => _setAvailability(game),
                                onDelete: () => _deleteGame(game),
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
  }

  List<Map<String, dynamic>> get _filteredGames {
    final games = _snapshot?.games ?? [];
    final query = _searchFocus.value;
    return games.where((game) {
      final matchesText =
          query.isEmpty ||
          (game['name'] as String? ?? '').toLowerCase().contains(query) ||
          (game['category'] as String? ?? '').toLowerCase().contains(query);
      final mode = game['game_mode'] as String? ?? 'time_based';
      final matchesChip =
          _selectedChip == 0 ||
          (_selectedChip == 1 && mode == 'match_based') ||
          (_selectedChip == 2 && mode != 'match_based');
      return matchesText && matchesChip;
    }).toList();
  }
}

class _GameFilterChip extends StatelessWidget {
  const _GameFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: selected
            ? const LinearGradient(
                colors: [Color(0xFF7A2FD6), Color(0xFFC026D3)],
              )
            : null,
        color: selected ? null : AppColors.surface2,
        border: Border.all(
          color: selected ? Colors.transparent : AppColors.line,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: selected ? Colors.white : AppColors.muted,
        ),
      ),
    ),
  );
}

class _GameCard extends StatelessWidget {
  const _GameCard({
    required this.game,
    required this.canManage,
    required this.onEdit,
    required this.onAvailability,
    required this.onDelete,
  });

  final Map<String, dynamic> game;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onAvailability;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isMatch = game['game_mode'] == 'match_based';
    final available = game['is_available'] as bool? ?? false;
    final imageUrl = game['image_url'] as String?;
    final youtubeUrl = game['youtube_url'] as String?;
    final hasYouTube = youtubeUrl != null && youtubeUrl.isNotEmpty;
    final platform = (game['platform'] as String? ?? 'PS5').toUpperCase();

    return Column(
      children: [
        // 1. Main Game Card
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: available
                    ? AppColors.line.withValues(alpha: 0.6)
                    : Colors.white10,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Poster image filling the entire card area
                  if (imageUrl == null || imageUrl.isEmpty)
                    const ColoredBox(
                      color: AppColors.surface2,
                      child: Center(
                        child: Icon(
                          Icons.sports_esports_rounded,
                          size: 52,
                          color: AppColors.primaryLight,
                        ),
                      ),
                    )
                  else
                    Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const ColoredBox(
                        color: AppColors.surface2,
                        child: Center(
                          child: Icon(
                            Icons.sports_esports_rounded,
                            size: 52,
                            color: AppColors.primaryLight,
                          ),
                        ),
                      ),
                    ),

                  // Dimmed overlay for disabled games
                  if (!available)
                    Container(
                      color: Colors.black.withValues(alpha: 0.65),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.red.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'غير متاح',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Dark gradient overlay for crystal-clear overlaid typography
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.25),
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.75),
                            Colors.black.withValues(alpha: 0.95),
                          ],
                          stops: const [0.0, 0.35, 0.75, 1.0],
                        ),
                      ),
                    ),
                  ),

                  // Floating top badges (Platform & Game Mode)
                  Positioned(
                    left: 10,
                    top: 10,
                    child: Row(
                      children: [
                        _GameBadge(text: platform),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: AppColors.primaryLight.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isMatch ? Icons.sports_soccer_rounded : Icons.timer_outlined,
                                size: 11,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                isMatch ? 'مباراة' : 'وقت',
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (hasYouTube) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.play_arrow_rounded, size: 11, color: Colors.white),
                                SizedBox(width: 2),
                                Text('YouTube', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Popup management menu in top right
                  if (canManage)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          shape: BoxShape.circle,
                        ),
                        child: PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert_rounded, color: Colors.white, size: 18),
                          onSelected: (value) {
                            if (value == 'edit') onEdit();
                            if (value == 'availability') onAvailability();
                            if (value == 'delete') onDelete();
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Text('Modifier'),
                            ),
                            PopupMenuItem(
                              value: 'availability',
                              child: Text(available ? 'Désactiver' : 'Réactiver'),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('Supprimer', style: TextStyle(color: AppColors.red)),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Overlaid typography & price badge at the bottom
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          game['name'] as String? ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            shadows: [
                              Shadow(color: Colors.black, blurRadius: 4),
                            ],
                          ),
                        ),
                        const SizedBox(height: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF7A2FD6), Color(0xFFC026D3)],
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${(game['price'] as num? ?? 0).toStringAsFixed(0)} DA · '
                            '${isMatch ? 'par match' : _priceUnit(game['pricing_unit'] as String?)}',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: 4),

        // 2. Realistic Water Reflection Effect below the Card
        SizedBox(
          height: 36,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(20),
            ),
            child: ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x55FFFFFF), // Soft reflection sheen at top
                  Color(0x00FFFFFF), // Fade out completely to transparent at bottom
                ],
                stops: [0.0, 0.85],
              ).createShader(bounds),
              blendMode: BlendMode.dstIn,
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.rotationX(3.14159), // Vertically flip for realistic reflection
                child: Opacity(
                  opacity: 0.30,
                  child: imageUrl == null || imageUrl.isEmpty
                      ? const ColoredBox(color: AppColors.surface2)
                      : Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const ColoredBox(color: AppColors.surface2),
                        ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GameBadge extends StatelessWidget {
  const _GameBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.bg.withValues(alpha: 0.85),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.5)),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w700,
        color: Color(0xFFD9C2FF),
      ),
    ),
  );
}

class _GameFormDialog extends StatefulWidget {
  const _GameFormDialog({required this.venueId, this.existing});

  final String venueId;
  final Map<String, dynamic>? existing;

  @override
  State<_GameFormDialog> createState() => _GameFormDialogState();
}

class _GameFormDialogState extends State<_GameFormDialog> {
  int _activeTab = 0; // 0: Général, 1: Mode & Durée, 2: Tarification

  late final _name = TextEditingController(
    text: widget.existing?['name'] as String? ?? '',
  );
  late final _price = TextEditingController(
    text: widget.existing?['price']?.toString() ?? '',
  );
  late final _category = TextEditingController(
    text: widget.existing?['category'] as String? ?? '',
  );
  late final _imageUrl = TextEditingController(
    text: widget.existing?['image_url'] as String? ?? '',
  );
  late final _youtubeUrl = TextEditingController(
    text: widget.existing?['youtube_url'] as String? ?? '',
  );
  late final _matchMinutes = TextEditingController(
    text: widget.existing?['match_minutes']?.toString() ?? '10',
  );
  late String _modeSource =
      widget.existing?['mode_source'] as String? ?? 'auto';
  late String _ownerMode =
      widget.existing?['game_mode'] as String? ?? 'time_based';
  late String _pricingUnit =
      widget.existing?['pricing_unit'] as String? ?? 'per_hour';
  late final Map<String, TextEditingController> _tierPrices = {
    '6': TextEditingController(
      text: (widget.existing?['pricing_tiers'] as Map?)?['6']?.toString() ?? '',
    ),
    '8': TextEditingController(
      text: (widget.existing?['pricing_tiers'] as Map?)?['8']?.toString() ?? '',
    ),
    '10': TextEditingController(
      text: (widget.existing?['pricing_tiers'] as Map?)?['10']?.toString() ?? '',
    ),
    '16': TextEditingController(
      text: (widget.existing?['pricing_tiers'] as Map?)?['16']?.toString() ?? '',
    ),
    '15': TextEditingController(
      text: (widget.existing?['pricing_tiers'] as Map?)?['15']?.toString() ?? '',
    ),
    '30': TextEditingController(
      text: (widget.existing?['pricing_tiers'] as Map?)?['30']?.toString() ?? '',
    ),
    '60': TextEditingController(
      text: (widget.existing?['pricing_tiers'] as Map?)?['60']?.toString() ?? '',
    ),
    '90': TextEditingController(
      text: (widget.existing?['pricing_tiers'] as Map?)?['90']?.toString() ?? '',
    ),
    '120': TextEditingController(
      text: (widget.existing?['pricing_tiers'] as Map?)?['120']?.toString() ?? '',
    ),
    '180': TextEditingController(
      text: (widget.existing?['pricing_tiers'] as Map?)?['180']?.toString() ?? '',
    ),
  };
  bool _uploadingImage = false;
  String? _imageError;
  late final _imageStorage = CatalogImageStorage(Supabase.instance.client);

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _category.dispose();
    _imageUrl.dispose();
    _youtubeUrl.dispose();
    _matchMinutes.dispose();
    for (final c in _tierPrices.values) {
      c.dispose();
    }
    super.dispose();
  }

  String get _resolvedMode {
    if (_modeSource == 'auto') {
      return GameClassificationService.classify(_name.text) ==
              GameClassification.footballMatch
          ? 'match_based'
          : 'time_based';
    }
    return _ownerMode;
  }

  Future<void> _pickImage() async {
    setState(() {
      _uploadingImage = true;
      _imageError = null;
    });
    try {
      final url = await _imageStorage.pickAndUpload(venueId: widget.venueId);
      if (url != null && mounted) {
        setState(() => _imageUrl.text = url);
      }
    } on CatalogImageException catch (error) {
      if (mounted) setState(() => _imageError = error.message);
    } on StorageException catch (error) {
      debugPrint('Téléversement de l’image du jeu impossible : $error');
      if (mounted) {
        setState(
          () => _imageError =
              'L’image n’a pas pu être envoyée. Vérifiez les droits Storage et réessayez.',
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Téléversement de l’image du jeu impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() => _imageError = 'L’image n’a pas pu être envoyée.');
      }
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = _resolvedMode;
    final isMatch = mode == 'match_based';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: AppSurface(
        borderRadius: 24,
        padding: EdgeInsets.zero,
        child: Container(
          width: 500,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 16, 14),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF7A2FD6), Color(0xFFC026D3)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.sports_esports_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.existing == null
                                ? 'Ajouter un jeu'
                                : 'Modifier le jeu',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.existing == null
                                ? 'Configurez le jeu et ses tarifs'
                                : widget.existing!['name'] as String? ?? '',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1, color: AppColors.line),

              // Segmented Tab Bar
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Row(
                    children: [
                      _buildTabButton(0, Icons.info_outline_rounded, 'Général'),
                      _buildTabButton(1, Icons.sports_esports_outlined, 'Mode'),
                      _buildTabButton(2, Icons.attach_money_rounded, 'Tarifs'),
                    ],
                  ),
                ),
              ),

              // Tab Content Area
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: switch (_activeTab) {
                      0 => _buildGeneralTab(),
                      1 => _buildModeTab(isMatch),
                      2 => _buildPricingTab(isMatch),
                      _ => const SizedBox.shrink(),
                    },
                  ),
                ),
              ),

              const Divider(height: 1, color: AppColors.line),

              // Footer Actions
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    if (_activeTab > 0)
                      TextButton.icon(
                        onPressed: () => setState(() => _activeTab--),
                        icon: const Icon(Icons.arrow_back_rounded, size: 16),
                        label: const Text('Précédent'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.muted,
                        ),
                      )
                    else
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.muted,
                        ),
                        child: const Text('Annuler'),
                      ),
                    const Spacer(),
                    if (_activeTab < 2)
                      FilledButton.icon(
                        onPressed: () => setState(() => _activeTab++),
                        iconAlignment: IconAlignment.end,
                        icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                        label: const Text('Suivant'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.surface1,
                          side: const BorderSide(color: AppColors.line),
                        ),
                      )
                    else
                      SizedBox(
                        width: 140,
                        child: AppButton(
                          label: 'Enregistrer',
                          onPressed: _uploadingImage ? () {} : _save,
                          icon: const Icon(Icons.check_rounded, size: 18),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabButton(int index, IconData icon, String label) {
    final selected = _activeTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _activeTab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: selected
                ? const LinearGradient(
                    colors: [Color(0xFF7A2FD6), Color(0xFFC026D3)],
                  )
                : null,
            color: selected ? null : Colors.transparent,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? Colors.white : AppColors.muted,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? Colors.white : AppColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGeneralTab() {
    return Column(
      key: const ValueKey(0),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Informations de base',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.primaryLight,
          ),
        ),
        const SizedBox(height: 10),
        AppTextField(
          hintText: 'Nom du jeu (ex: EA FC 24, Tekken 8...)',
          controller: _name,
          prefixIcon: const Icon(Icons.sports_esports_outlined),
          onChanged: (_) => setState(() {}),
        ),
        if (_name.text.trim().isNotEmpty && _modeSource == 'auto') ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Icon(
                  _resolvedMode == 'match_based'
                      ? Icons.sports_soccer_rounded
                      : Icons.timer_outlined,
                  size: 14,
                  color: AppColors.primaryLight,
                ),
                const SizedBox(width: 6),
                Text(
                  _resolvedMode == 'match_based'
                      ? 'Détection auto : Mode Match (Football)'
                      : 'Détection auto : Mode Temps (Durée)',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryLight,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        AppTextField(
          hintText: 'Catégorie (ex: Football, Combat, Course)',
          controller: _category,
          prefixIcon: const Icon(Icons.category_outlined),
        ),
        const SizedBox(height: 18),
        const Text(
          'Image de couverture',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.primaryLight,
          ),
        ),
        const SizedBox(height: 10),

        // Image Preview & Upload Dropzone Card
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.line),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              if (_imageUrl.text.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    alignment: Alignment.topRight,
                    children: [
                      Image.network(
                        _imageUrl.text,
                        height: 110,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          height: 100,
                          color: AppColors.bg,
                          alignment: Alignment.center,
                          child: const Text(
                            'Aperçu indisponible',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.muted,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(() => _imageUrl.clear()),
                        icon: const Icon(
                          Icons.cancel_rounded,
                          color: Colors.white,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _uploadingImage ? null : _pickImage,
                      icon: _uploadingImage
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.cloud_upload_rounded, size: 18),
                      label: Text(
                        _uploadingImage
                            ? 'Téléversement…'
                            : 'Choisir une image',
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.line),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (_imageError != null) ...[
                const SizedBox(height: 6),
                Text(
                  _imageError!,
                  style: const TextStyle(color: AppColors.red, fontSize: 11),
                ),
              ],
              const SizedBox(height: 8),
              AppTextField(
                hintText: 'Ou coller l’URL de l’image ici...',
                controller: _imageUrl,
                prefixIcon: const Icon(Icons.link_rounded),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              AppTextField(
                hintText: 'Lien YouTube (trailer / présentation, facultatif)',
                controller: _youtubeUrl,
                prefixIcon: const Icon(Icons.play_circle_outline_rounded),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModeTab(bool isMatch) {
    return Column(
      key: const ValueKey(1),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Mode de détection du jeu',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.primaryLight,
          ),
        ),
        const SizedBox(height: 10),

        // Auto / Custom Cards
        Row(
          children: [
            Expanded(
              child: _buildSelectCard(
                title: 'Automatique',
                subtitle: 'Détecté par nom',
                icon: Icons.auto_awesome_rounded,
                selected: _modeSource == 'auto',
                onTap: () => setState(() => _modeSource = 'auto'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildSelectCard(
                title: 'Personnalisé',
                subtitle: 'Choix manuel',
                icon: Icons.tune_rounded,
                selected: _modeSource == 'owner',
                onTap: () => setState(() => _modeSource = 'owner'),
              ),
            ),
          ],
        ),

        if (_modeSource == 'owner') ...[
          const SizedBox(height: 16),
          const Text(
            'Mode personnalisé',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryLight,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildSelectCard(
                  title: 'Par Match',
                  subtitle: 'Facturation/match',
                  icon: Icons.sports_soccer_rounded,
                  selected: _ownerMode == 'match_based',
                  onTap: () {
                    setState(() {
                      _ownerMode = 'match_based';
                      _pricingUnit = 'per_match';
                    });
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildSelectCard(
                  title: 'Par Durée',
                  subtitle: 'Facturation/temps',
                  icon: Icons.timer_outlined,
                  selected: _ownerMode == 'time_based',
                  onTap: () {
                    setState(() {
                      _ownerMode = 'time_based';
                      if (_pricingUnit == 'per_match') {
                        _pricingUnit = 'per_hour';
                      }
                    });
                  },
                ),
              ),
            ],
          ),
        ],

        if (isMatch) ...[
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.sports_soccer_rounded, color: AppColors.primaryLight, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Les باقات المباريات (6د، 8د، 10د، 16د) تُحدد أسعارها في تبويب Tarifs.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.primaryLight,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPricingTab(bool isMatch) {
    return Column(
      key: const ValueKey(2),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tarif de base',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.primaryLight,
          ),
        ),
        const SizedBox(height: 10),

        Row(
          children: [
            Expanded(
              flex: 3,
              child: AppTextField(
                hintText: 'Prix (ex: 200)',
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                prefixIcon: const Icon(Icons.payments_outlined),
                suffixIcon: const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Text(
                    'DA',
                    style: TextStyle(
                      color: AppColors.primaryLight,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            if (!isMatch) ...[
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: AppColors.surface1,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _pricingUnit,
                      isExpanded: true,
                      dropdownColor: AppColors.surface1,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.text,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'per_hour',
                          child: Text('Par heure'),
                        ),
                        DropdownMenuItem(
                          value: 'per_30_minutes',
                          child: Text('Par 30 min'),
                        ),
                        DropdownMenuItem(
                          value: 'per_15_minutes',
                          child: Text('Par 15 min'),
                        ),
                        DropdownMenuItem(
                          value: 'per_minute',
                          child: Text('Par minute'),
                        ),
                        DropdownMenuItem(
                          value: 'fixed_price',
                          child: Text('Forfait fixe'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _pricingUnit = value);
                        }
                      },
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),

        const SizedBox(height: 18),
        Text(
          isMatch
              ? 'أسعار باقات المباريات (Match Packages)'
              : 'Tarifs spécifiques par durée et forfait',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.primaryLight,
          ),
        ),
        const SizedBox(height: 10),

        // Tiers 2-column Grid
        LayoutBuilder(
          builder: (context, constraints) {
            final tierKeys = isMatch
                ? ['6', '8', '10', '16']
                : ['15', '30', '60', '90', '120', '180'];
            final tierLabels = {
              '6': 'Match 6 min',
              '8': 'Match 8 min',
              '10': 'Match 10 min',
              '16': 'Match 16 min',
              '15': 'Forfait 15 min',
              '30': 'Forfait 30 min',
              '60': 'Forfait 1 heure',
              '90': 'Forfait 1h 30 min',
              '120': 'Forfait 2 heures',
              '180': 'Forfait 3 heures',
            };

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: tierKeys.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                mainAxisExtent: 48,
              ),
              itemBuilder: (context, index) {
                final key = tierKeys[index];
                return AppTextField(
                  hintText: tierLabels[key] ?? '$key min',
                  controller: _tierPrices[key],
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  suffixIcon: const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Text(
                      'DA',
                      style: TextStyle(color: AppColors.muted, fontSize: 11),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildSelectCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.15)
              : AppColors.surface2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.primaryLight : AppColors.line,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: selected ? AppColors.primaryLight : AppColors.muted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: selected ? AppColors.text : AppColors.muted,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 10,
                      color: selected
                          ? AppColors.primaryLight
                          : AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    final name = _name.text.trim();
    final price = double.tryParse(_price.text.replaceAll(',', '.'));
    final mode = _resolvedMode;
    if (name.isEmpty || price == null || price < 0) {
      return;
    }

    final matchMinutes = mode == 'match_based'
        ? (int.tryParse(_matchMinutes.text) ?? 10)
        : null;

    final pricingTiers = <String, double>{};
    for (final entry in _tierPrices.entries) {
      final val = double.tryParse(entry.value.text.trim().replaceAll(',', '.'));
      if (val != null && val >= 0) {
        pricingTiers[entry.key] = val;
      }
    }

    final multiplier = mode == 'match_based'
        ? const GameTimingPolicy().multiplierFor(name)
        : 1.0;
    Navigator.pop(context, {
      'name': name,
      'category': _category.text.trim().isEmpty ? null : _category.text.trim(),
      'image_url': _imageUrl.text.trim().isEmpty ? null : _imageUrl.text.trim(),
      'youtube_url': _youtubeUrl.text.trim().isEmpty ? null : _youtubeUrl.text.trim(),
      'game_mode': mode,
      'mode_source': _modeSource,
      'pricing_unit': mode == 'match_based' ? 'per_match' : _pricingUnit,
      'price': price,
      'match_minutes': mode == 'match_based' ? matchMinutes : null,
      'time_multiplier': multiplier,
      'pricing_tiers': pricingTiers,
      'is_available': widget.existing?['is_available'] ?? true,
    });
  }
}

class _GameNotice extends StatelessWidget {
  const _GameNotice({required this.text, required this.onRetry});

  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => AppSurface(
    borderRadius: 16,
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 12, color: AppColors.red),
          ),
        ),
        IconButton(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded)),
      ],
    ),
  );
}

class _GameEmptyState extends StatelessWidget {
  const _GameEmptyState();

  @override
  Widget build(BuildContext context) => const AppSurface(
    borderRadius: 20,
    child: Column(
      children: [
        Icon(Icons.sports_esports_rounded, size: 38, color: AppColors.muted),
        SizedBox(height: 12),
        Text(
          'Aucun jeu dans le catalogue',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 6),
        Text(
          'Les jeux ajoutés par la gestion apparaîtront ici.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppColors.muted),
        ),
      ],
    ),
  );
}

String _priceUnit(String? unit) => switch (unit) {
  'per_minute' => 'par minute',
  'per_15_minutes' => 'par 15 min',
  'per_30_minutes' => 'par 30 min',
  'fixed_price' => 'forfait fixe',
  _ => 'par heure',
};

class _CustomerGameCarouselView extends StatefulWidget {
  const _CustomerGameCarouselView({required this.games});
  final List<Map<String, dynamic>> games;

  @override
  State<_CustomerGameCarouselView> createState() => _CustomerGameCarouselViewState();
}

class _CustomerGameCarouselViewState extends State<_CustomerGameCarouselView> {
  late final PageController _pageController;
  double _currentPage = 0.0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.82);
    _pageController.addListener(() {
      if (mounted) {
        setState(() {
          _currentPage = _pageController.page ?? 0.0;
        });
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.games.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 60),
        child: Center(
          child: Text(
            'Aucun jeu disponible',
            style: TextStyle(color: AppColors.muted, fontSize: 14),
          ),
        ),
      );
    }

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.56,
      child: PageView.builder(
        controller: _pageController,
        itemCount: widget.games.length,
        itemBuilder: (context, index) {
          final game = widget.games[index];
          final diff = (_currentPage - index).abs();
          final scale = (1.0 - (diff * 0.12)).clamp(0.85, 1.0);

          return Center(
            child: Transform.scale(
              scale: scale,
              child: _LargeCarouselGameCard(game: game),
            ),
          );
        },
      ),
    );
  }
}

class _LargeCarouselGameCard extends StatelessWidget {
  const _LargeCarouselGameCard({required this.game});
  final Map<String, dynamic> game;

  @override
  Widget build(BuildContext context) {
    final isMatch = game['game_mode'] == 'match_based';
    final imageUrl = game['image_url'] as String?;
    final platform = (game['platform'] as String? ?? 'PS5').toUpperCase();
    final name = game['name'] as String? ?? 'Jeu';
    final subtitle = game['subtitle'] as String?;
    final price = (game['price'] as num? ?? 0).toDouble();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF35226E), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl == null || imageUrl.isEmpty)
              const ColoredBox(
                color: AppColors.surface2,
                child: Center(
                  child: Icon(
                    Icons.sports_esports_rounded,
                    size: 64,
                    color: AppColors.primaryLight,
                  ),
                ),
              )
            else
              Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const ColoredBox(
                  color: AppColors.surface2,
                  child: Center(
                    child: Icon(
                      Icons.sports_esports_rounded,
                      size: 64,
                      color: AppColors.primaryLight,
                    ),
                  ),
                ),
              ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.3),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.8),
                      Colors.black.withValues(alpha: 0.95),
                    ],
                    stops: const [0.0, 0.3, 0.7, 1.0],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              top: 16,
              child: Row(
                children: [
                  _GameBadge(text: platform),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isMatch ? Icons.sports_soccer_rounded : Icons.timer_outlined,
                          size: 13,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isMatch ? 'Match' : 'Temps',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      shadows: [Shadow(color: Colors.black, blurRadius: 6)],
                    ),
                  ),
                  if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF7A2FD6), Color(0xFFC026D3)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${price.toStringAsFixed(0)} DA · ${isMatch ? 'Par match' : 'Par heure'}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
