import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/app_bottom_nav.dart';
import '../../../app/widgets/app_widgets.dart';
import '../../../app/widgets/responsive_scaffold.dart';
import '../../../core/data/venue_repository.dart';
import '../data/reports_repository.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late final ReportsRepository _repository;
  ReportsSnapshot? _snapshot;
  Object? _error;
  ReportPeriod _period = ReportPeriod.today;
  bool _loading = true;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _repository = ReportsRepository(Supabase.instance.client);
    _load();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snapshot = await _repository.load(_period);
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _snapshot = snapshot);
    } on PostgrestException catch (error) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _error = error);
      }
    } on VenueRepositoryException catch (error) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _error = error);
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  void _selectPeriod(ReportPeriod period) {
    if (period == _period) return;
    setState(() {
      _period = period;
      _snapshot = null;
    });
    _load();
  }

  Future<void> _exportCsv() async {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    final csv = StringBuffer()
      ..writeln('Rapport;${_period.label}')
      ..writeln('Indicateur;Valeur')
      ..writeln('Revenu total;${snapshot.revenue.toStringAsFixed(2)} DA')
      ..writeln('Matchs joués;${snapshot.matchCount}')
      ..writeln(
        'Ventes produits;${snapshot.productRevenue.toStringAsFixed(2)} DA',
      )
      ..writeln('Articles vendus;${snapshot.productUnits}')
      ..writeln(
        'Durée de jeu;${_formatDuration(snapshot.gamingDurationSeconds)}',
      )
      ..writeln()
      ..writeln('Revenus par jeu')
      ..writeln('Jeu;Matchs;Durée (h);Revenu (DA)');
    for (final game in snapshot.gameRevenue) {
      csv.writeln(
        '${_csvValue(game.name)};${game.matchCount};'
        '${(game.durationSeconds / 3600).toStringAsFixed(2)};'
        '${game.revenue.toStringAsFixed(2)}',
      );
    }
    csv
      ..writeln()
      ..writeln('Produits les plus vendus')
      ..writeln('Produit;Quantité;Revenu (DA)');
    for (final product in snapshot.topProducts) {
      csv.writeln(
        '${_csvValue(product.name)};${product.quantity};'
        '${product.revenue.toStringAsFixed(2)}',
      );
    }

    await Clipboard.setData(ClipboardData(text: csv.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Rapport CSV copié dans le presse-papiers.'),
      ),
    );
  }

  String _csvValue(String value) => '"${value.replaceAll('"', '""')}"';

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final maxRevenue =
        snapshot?.gameRevenue.fold<double>(
          0,
          (current, game) => game.revenue > current ? game.revenue : current,
        ) ??
        0;

    return ResponsiveScaffold(
      currentIndex: 3,
      isStaff: true,
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 24),
            children: [
                    AppPageHeader(onBack: () => context.pop()),
                    const SizedBox(height: 18),
                    AppScreenTitle(
                      title: 'Rapports',
                      subtitle: 'Statistiques financières & lounge',
                      trailing: IconButton(
                        tooltip: 'Exporter le rapport CSV',
                        onPressed: snapshot == null ? null : _exportCsv,
                        icon: const Icon(Icons.file_download_outlined),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _PeriodSelector(
                      selected: _period,
                      onSelected: _selectPeriod,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      AppSurface(
                        borderRadius: 18,
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              color: AppColors.red,
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Les rapports n’ont pas pu être chargés.',
                                style: TextStyle(
                                  color: AppColors.red,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Réessayer',
                              onPressed: _load,
                              icon: const Icon(Icons.refresh_rounded),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_loading && snapshot == null)
                      const SizedBox(
                        height: 220,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (snapshot != null) ...[
                      if (_loading) ...[
                        const SizedBox(height: 12),
                        const LinearProgressIndicator(minHeight: 2),
                      ],
                      const SizedBox(height: 14),
                      _buildKpis(context, snapshot),
                      const SizedBox(height: 14),
                      _RevenueChart(snapshot: snapshot),
                      const SizedBox(height: 14),
                      _buildGamesCard(snapshot, maxRevenue),
                      const SizedBox(height: 14),
                      _buildProductsCard(snapshot),
                    ] else if (_error == null) ...[
                      const SizedBox(
                        height: 220,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
  }

  Widget _buildKpis(BuildContext context, ReportsSnapshot snapshot) =>
      LayoutBuilder(
        builder: (context, constraints) {
          const gap = 12.0;
          final width = (constraints.maxWidth - gap) / 2;
          final occupiedPercent = (snapshot.occupancyRate * 100).round();
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              _ReportKpi(
                width: width,
                label: 'Revenu total',
                value: '${snapshot.revenue.toStringAsFixed(0)} DA',
                detail: _period.label,
                icon: Icons.payments_outlined,
                selected: true,
              ),
              _ReportKpi(
                width: width,
                label: 'Matchs joués',
                value: '${snapshot.matchCount}',
                detail: 'Sessions clôturées',
                icon: Icons.sports_esports_rounded,
              ),
              _ReportKpi(
                width: width,
                label: 'Ventes de produits',
                value: '${snapshot.productRevenue.toStringAsFixed(0)} DA',
                detail: '${snapshot.productUnits} articles vendus',
                icon: Icons.local_cafe_outlined,
              ),
              _ReportKpi(
                width: width,
                label: 'Temps de jeu cumulé',
                value: _formatDuration(snapshot.gamingDurationSeconds),
                detail: snapshot.postCount == 0
                    ? 'Aucun poste configuré'
                    : 'Occupation estimée : $occupiedPercent%',
                icon: Icons.timer_outlined,
              ),
            ],
          );
        },
      );

  Widget _buildGamesCard(ReportsSnapshot snapshot, double maxRevenue) =>
      _ReportCard(
        title: 'Rentabilité par jeu',
        subtitle: 'Sessions clôturées et parts de revenus',
        child: snapshot.gameRevenue.isEmpty
            ? const _EmptyReport(
                message: 'Aucune session clôturée sur cette période.',
              )
            : Column(
                children: [
                  for (final game in snapshot.gameRevenue)
                    _GameRevenueRow(game: game, maxRevenue: maxRevenue),
                ],
              ),
      );

  Widget _buildProductsCard(ReportsSnapshot snapshot) => _ReportCard(
    title: 'Top consommations & bar',
    subtitle: 'Produits vendus sur la période',
    child: snapshot.topProducts.isEmpty
        ? const _EmptyReport(
            message: 'Aucune vente de produit sur cette période.',
          )
        : Column(
            children: [
              for (final product in snapshot.topProducts)
                _ProductSalesRow(product: product),
            ],
          ),
  );
}

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({required this.selected, required this.onSelected});

  final ReportPeriod selected;
  final ValueChanged<ReportPeriod> onSelected;

  @override
  Widget build(BuildContext context) => AppSurface(
    borderRadius: 16,
    padding: const EdgeInsets.all(5),
    child: Row(
      children: [
        for (final period in ReportPeriod.values)
          Expanded(
            child: Semantics(
              button: true,
              selected: period == selected,
              child: GestureDetector(
                onTap: () => onSelected(period),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: period == selected
                        ? AppColors.primary.withValues(alpha: 0.22)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    period.label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: period == selected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: period == selected
                          ? Colors.white
                          : AppColors.muted,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _ReportKpi extends StatelessWidget {
  const _ReportKpi({
    required this.width,
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    this.selected = false,
  });

  final double width;
  final String label;
  final String value;
  final String detail;
  final IconData icon;
  final bool selected;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: 128,
    child: AppSurface(
      isSelected: selected,
      borderRadius: 22,
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppColors.muted,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(icon, size: 16, color: AppColors.pink),
            ],
          ),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, color: AppColors.muted),
          ),
        ],
      ),
    ),
  );
}

class _RevenueChart extends StatelessWidget {
  const _RevenueChart({required this.snapshot});

  final ReportsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final buckets = snapshot.revenueBuckets;
    final maxRevenue = buckets.fold<double>(
      0,
      (current, bucket) => bucket.revenue > current ? bucket.revenue : current,
    );
    final peak = buckets.isEmpty
        ? null
        : buckets.reduce(
            (current, bucket) =>
                bucket.revenue > current.revenue ? bucket : current,
          );
    final singleDay = buckets.length == 24;
    final itemWidth = buckets.length <= 8 ? 32.0 : 25.0;
    final chartWidth = buckets.length * itemWidth;

    return _ReportCard(
      title: 'Évolution du chiffre d’affaires',
      subtitle: singleDay ? 'Activité horaire' : 'Activité journalière',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 142,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: chartWidth,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < buckets.length; i++)
                      SizedBox(
                        width: itemWidth,
                        child: Column(
                          children: [
                            Expanded(
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: Container(
                                  width: itemWidth * 0.48,
                                  height: maxRevenue == 0
                                      ? 2
                                      : (buckets[i].revenue / maxRevenue * 104)
                                            .clamp(2, 104),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(5),
                                    gradient: const LinearGradient(
                                      begin: Alignment.bottomCenter,
                                      end: Alignment.topCenter,
                                      colors: [
                                        AppColors.primary,
                                        AppColors.pink,
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 18,
                              child: Text(
                                _showBucketLabel(i, buckets.length)
                                    ? buckets[i].label
                                    : '',
                                maxLines: 1,
                                style: const TextStyle(
                                  fontSize: 8,
                                  color: AppColors.muted,
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
          const SizedBox(height: 10),
          AppSurface(
            borderRadius: 14,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                const Icon(
                  Icons.trending_up_rounded,
                  size: 17,
                  color: AppColors.pink,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    peak == null || peak.revenue == 0
                        ? 'Aucun revenu enregistré sur cette période.'
                        : 'Pic à ${peak.label} · ${peak.revenue.toStringAsFixed(0)} DA',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _showBucketLabel(int index, int count) {
    if (count == 24) return index % 4 == 0;
    if (count > 12) return index % 4 == 0 || index == count - 1;
    return true;
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => AppSurface(
    borderRadius: 24,
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 11, color: AppColors.muted),
        ),
        const SizedBox(height: 14),
        child,
      ],
    ),
  );
}

class _EmptyReport extends StatelessWidget {
  const _EmptyReport({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(
      message,
      style: const TextStyle(fontSize: 12, color: AppColors.muted),
    ),
  );
}

class _GameRevenueRow extends StatelessWidget {
  const _GameRevenueRow({required this.game, required this.maxRevenue});

  final GameRevenue game;
  final double maxRevenue;

  @override
  Widget build(BuildContext context) {
    final ratio = maxRevenue == 0 ? 0.0 : game.revenue / maxRevenue;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(
                colors: [AppColors.primary, Color(0xFFC026D3)],
              ),
            ),
            child: const Icon(
              Icons.sports_esports_rounded,
              size: 19,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  game.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${game.matchCount} matchs · ${_formatDuration(game.durationSeconds)}',
                  style: const TextStyle(fontSize: 10, color: AppColors.muted),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 5,
                    backgroundColor: const Color(0xFF292943),
                    valueColor: const AlwaysStoppedAnimation(AppColors.pink),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${game.revenue.toStringAsFixed(0)} DA',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _ProductSalesRow extends StatelessWidget {
  const _ProductSalesRow({required this.product});

  final ProductSales product;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      children: [
        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.local_cafe_outlined,
            size: 19,
            color: AppColors.pink,
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                product.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${product.quantity} articles vendus',
                style: const TextStyle(fontSize: 10, color: AppColors.muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '${product.revenue.toStringAsFixed(0)} DA',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

String _formatDuration(int seconds) {
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (hours == 0) return '${minutes}m';
  if (minutes == 0) return '${hours}h';
  return '${hours}h ${minutes}m';
}
