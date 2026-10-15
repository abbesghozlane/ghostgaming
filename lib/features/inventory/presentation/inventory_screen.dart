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
import '../../../core/offline/offline_operation_queue.dart';
import '../../../core/storage/catalog_image_storage.dart';
import '../../../core/utils/operation_id.dart';
import '../../customers/data/customer_repository.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _client = Supabase.instance.client;
  final _searchController = TextEditingController();
  VenueContext? _venue;
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _categories = [];
  CustomerHomeSnapshot? _customerSnapshot;
  RealtimeChannel? _channel;
  Timer? _refreshDebounce;
  int _selectedChip = 0;
  bool _loading = true;
  bool _working = false;
  String? _error;
  final List<String> _chips = ['Tous', 'Stock faible', 'Indisponibles'];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _refreshDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final venue = await VenueRepository(_client).currentVenue();
      final results = await Future.wait([
        _client
            .from('products')
            .select(
              'id, name, category_id, sale_price, cost_price, stock_quantity, '
              'minimum_stock, is_available, image_url',
            )
            .eq('venue_id', venue.id)
            .order('name'),
        _client
            .from('product_categories')
            .select('id, name')
            .eq('venue_id', venue.id)
            .order('sort_order')
            .order('name'),
      ]);

      CustomerHomeSnapshot? customerSnapshot;
      if (venue.role == 'customer') {
        try {
          customerSnapshot = await CustomerRepository(_client).loadHome();
        } catch (_) {}
      }

      if (!mounted) return;
      final venueChanged = _venue?.id != venue.id;
      setState(() {
        _venue = venue;
        _products = (results[0] as List<dynamic>).cast<Map<String, dynamic>>();
        _categories = (results[1] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        _customerSnapshot = customerSnapshot;
        _error = null;
      });
      if (venueChanged) _subscribe(venue.id);
    } on PostgrestException catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error.message));
    } on VenueRepositoryException catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error.code));
    } catch (error, stackTrace) {
      debugPrint('Chargement du stock impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) setState(() => _error = 'Le stock n’a pas pu être chargé.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _subscribe(String venueId) {
    _channel?.unsubscribe();
    _channel = _client.channel(
      'venue:$venueId:inventory',
      opts: const RealtimeChannelConfig(private: true),
    );
    for (final event in ['INSERT', 'UPDATE', 'DELETE']) {
      _channel!.onBroadcast(
        event: event,
        callback: (_) {
          _refreshDebounce?.cancel();
          _refreshDebounce = Timer(const Duration(milliseconds: 250), _load);
        },
      );
    }
    _channel!.subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut) {
        debugPrint('Avertissement Realtime (stock): $status, $error');
      }
    });
  }

  Future<void> _orderCustomerProduct(Map<String, dynamic> product) async {
    final stock = (product['stock_quantity'] as num?)?.toInt() ?? 0;
    if (stock < 1 || _working) return;

    final sessions = _customerSnapshot?.sessions ?? const [];
    final activeSession = sessions.where((s) => s['status'] == 'active').toList();
    final sessionId = activeSession.isNotEmpty ? activeSession.first['id'] as String? : null;
    final canAddToSession = sessionId != null;

    final quantity = await showDialog<_ProductOrderSelection>(
      context: context,
      builder: (context) => _ProductOrderDialog(
        name: product['name'] as String? ?? 'Produit',
        price: (product['sale_price'] as num).toDouble(),
        stock: stock,
        canAddToSession: canAddToSession,
      ),
    );
    if (quantity == null || !mounted) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final repo = CustomerRepository(_client);
      if (quantity.addToSession) {
        if (sessionId == null) {
          throw const CustomerFlowException('Aucune session active pour cette commande.');
        }
        await repo.addProductToSession(
          sessionId: sessionId,
          productId: product['id'] as String,
          quantity: quantity.quantity,
          expectedUnitPrice: (product['sale_price'] as num).toDouble(),
        );
      } else {
        await repo.requestStandaloneProductOrder(
          productId: product['id'] as String,
          quantity: quantity.quantity,
          expectedUnitPrice: (product['sale_price'] as num).toDouble(),
          paymentMethod: quantity.paymentMethod,
        );
      }
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              quantity.addToSession
                  ? 'Produit ajouté à la facture de votre session.'
                  : 'Demande envoyée. Réglez la commande au comptoir.',
            ),
          ),
        );
      }
    } on PostgrestException catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error.message));
    } catch (error, stackTrace) {
      debugPrint('Commande client impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() => _error = 'Le produit n’a pas pu être commandé.');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _addProduct() async {
    final venue = _venue;
    if (venue == null || !venue.canManageCatalog) return;
    final values = await showDialog<_ProductFormValue>(
      context: context,
      builder: (context) =>
          _ProductFormDialog(categories: _categories, venueId: venue.id),
    );
    if (values == null) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await _client.from('products').insert({
        'venue_id': venue.id,
        'name': values.name,
        'category_id': values.categoryId,
        'sale_price': values.salePrice,
        'cost_price': values.costPrice,
        'minimum_stock': values.minimumStock,
        'image_url': values.imageUrl.isEmpty ? null : values.imageUrl,
        'stock_quantity': 0,
      });
      await _load();
    } on PostgrestException catch (error) {
      setState(() => _error = _friendlyError(error.message));
    } catch (error, stackTrace) {
      debugPrint('Création du produit impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      setState(() => _error = 'Le produit n’a pas pu être créé.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _adjustStock(
    Map<String, dynamic> product, {
    required bool isRestock,
  }) async {
    final values = await showDialog<_StockAdjustmentValue>(
      context: context,
      builder: (context) => _StockAdjustmentDialog(
        productName: product['name'] as String,
        currentStock: (product['stock_quantity'] as num).toInt(),
        isRestock: isRestock,
      ),
    );
    if (values == null) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await executeIdempotentRpc<void>(_client, 'adjust_product_stock', {
        'p_op': OperationId.create(),
        'p_product': product['id'],
        'p_delta': values.delta,
        'p_reason': values.reason,
        'p_note': values.note,
      });
      await _load();
    } on PostgrestException catch (error) {
      final isStockShortage = error.message.contains('INSUFFICIENT_STOCK');
      setState(() {
        _error = isRestock && isStockShortage
            ? 'La base de données a refusé le réapprovisionnement. Vérifiez que les migrations Supabase sont à jour.'
            : _friendlyError(error.message);
      });
    } catch (error, stackTrace) {
      debugPrint('Mouvement de stock impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      setState(() => _error = 'Erreur : $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _restockProduct() async {
    if (_working) return;
    if (_products.isEmpty) {
      setState(
        () => _error = 'Créez d’abord un produit avant de réapprovisionner.',
      );
      return;
    }
    final product = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _RestockProductDialog(products: _products),
    );
    if (product != null && mounted) {
      await _adjustStock(product, isRestock: true);
    }
  }

  Future<void> _sellProduct(Map<String, dynamic> product) async {
    final sale = await showDialog<_SaleValue>(
      context: context,
      builder: (context) => _SaleDialog(
        productName: product['name'] as String,
        unitPrice: (product['sale_price'] as num).toDouble(),
        stockQuantity: (product['stock_quantity'] as num).toInt(),
      ),
    );
    if (sale == null) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final result =
          await executeIdempotentRpc<Object?>(_client, 'sell_product', {
            'p_op': OperationId.create(),
            'p_product': product['id'],
            'p_quantity': sale.quantity,
            'p_method': sale.method,
          });
      await _load();
      if (mounted) {
        final receipt = Map<String, dynamic>.from(result as Map);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Vente enregistrée · Facture n° ${receipt['invoice_number']} · '
              '${(receipt['total'] as num).toStringAsFixed(0)} DA',
            ),
          ),
        );
      }
    } on PostgrestException catch (error) {
      setState(() => _error = _friendlyError(error.message));
    } catch (error, stackTrace) {
      debugPrint('Vente du produit impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      setState(() => _error = 'La vente n’a pas pu être enregistrée.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _toggleAvailability(Map<String, dynamic> product) async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await _client
          .from('products')
          .update({
            'is_available': !(product['is_available'] as bool? ?? false),
          })
          .eq('id', product['id']);
      await _load();
    } on PostgrestException catch (error) {
      setState(() => _error = _friendlyError(error.message));
    } catch (error, stackTrace) {
      debugPrint('Modification du produit impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      setState(() => _error = 'La disponibilité du produit n’a pas changé.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String _friendlyError(String message) {
    final code = message.split(':').first.trim();
    return switch (code) {
      'FORBIDDEN' || '42501' => 'Votre rôle ne permet pas cette opération.',
      'INSUFFICIENT_STOCK' => 'Le stock disponible est insuffisant.',
      'PRODUCT_NOT_FOUND' => 'Ce produit est introuvable.',
      'PRODUCT_NOT_AVAILABLE' => 'Ce produit n’est plus disponible.',
      'INVALID_QUANTITY' => 'Saisissez une quantité valide.',
      'PAYMENT_TOTAL_MISMATCH' =>
        'Le montant du paiement ne correspond pas au total.',
      'STOCK_MUTATION_REQUIRES_RPC' =>
        'Le stock ne peut être modifié que par un mouvement tracé.',
      '23514' => 'Vérifiez le prix, le coût et le seuil de stock.',
      '23503' => 'La catégorie sélectionnée n’est plus disponible.',
      'VENUE_NOT_FOUND' => 'Aucune salle n’est associée à votre compte.',
      _ => message,
    };
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredProducts;
    final canManageCatalog = _venue?.canManageCatalog ?? false;
    final canManageStock = _venue?.canManageStock ?? false;
    final isCustomer = (_venue?.role ?? CurrentRoleCache.role) == 'customer';

    return ResponsiveScaffold(
      currentIndex: isCustomer ? 3 : 2,
      isStaff: !isCustomer,
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                  children: [
                    AppPageHeader(
                      onBack: () => context.go(isCustomer ? '/customer/home' : '/home'),
                      trailing: canManageCatalog
                          ? IconButton.filled(
                              tooltip: 'Ajouter un produit',
                              onPressed: _working ? null : _addProduct,
                              icon: const Icon(Icons.add_rounded),
                            )
                          : null,
                    ),
                    const SizedBox(height: 18),
                    AppScreenTitle(
                      title: isCustomer ? 'Snack & Boissons' : 'Inventaire',
                      subtitle: isCustomer
                          ? 'Commandez vos en-cas et boissons pour la session'
                          : (_venue?.name ?? 'Produits et mouvements de stock'),
                    ),
                    if (canManageStock) ...[
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _working ? null : _restockProduct,
                          icon: const Icon(Icons.add_box_outlined),
                          label: const Text('Réapprovisionner le stock'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    AppTextField(
                      hintText: 'Rechercher un produit...',
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
                        itemBuilder: (context, index) => _InventoryChip(
                          label: _chips[index],
                          selected: _selectedChip == index,
                          onTap: () => setState(() => _selectedChip = index),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      _InventoryNotice(text: _error!, onRetry: _load),
                    ],
                    if (_loading && _products.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 34),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (filtered.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 18),
                        child: _InventoryEmpty(),
                      )
                    else ...[
                      if (isCustomer) ...[
                        const SizedBox(height: 14),
                        _CustomerSnackCarousel(
                          products: _products,
                          onOrder: _orderCustomerProduct,
                        ),
                        const SizedBox(height: 22),
                        const Text(
                          'TOUS LES SNACKS & BOISSONS',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2.2,
                            color: AppColors.muted,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      const SizedBox(height: 6),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth > 650) {
                            final cols = constraints.maxWidth > 1050 ? 3 : 2;
                            return GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: filtered.length,
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: cols,
                                crossAxisSpacing: 14,
                                mainAxisSpacing: 14,
                                mainAxisExtent: 180,
                              ),
                              itemBuilder: (context, index) {
                                final product = filtered[index];
                                return isCustomer
                                    ? _customerProductCard(product)
                                    : _productCard(
                                        product,
                                        canManageCatalog: canManageCatalog,
                                        canManageStock: canManageStock,
                                      );
                              },
                            );
                          }
                          return Column(
                            children: filtered
                                .map(
                                  (product) => isCustomer
                                      ? _customerProductCard(product)
                                      : _productCard(
                                          product,
                                          canManageCatalog: canManageCatalog,
                                          canManageStock: canManageStock,
                                        ),
                                )
                                .toList(),
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

  List<Map<String, dynamic>> get _filteredProducts {
    final search = _searchController.text.trim().toLowerCase();
    return _products.where((product) {
      final matchesSearch =
          search.isEmpty ||
          (product['name'] as String).toLowerCase().contains(search);
      final stock = (product['stock_quantity'] as num).toInt();
      final minimum = (product['minimum_stock'] as num).toInt();
      final available = product['is_available'] as bool? ?? false;
      final matchesFilter = switch (_selectedChip) {
        1 => stock <= minimum,
        2 => !available,
        _ => true,
      };
      return matchesSearch && matchesFilter;
    }).toList();
  }

  Widget _customerProductCard(Map<String, dynamic> product) {
    final name = product['name'] as String? ?? 'Produit';
    final price = (product['sale_price'] as num?)?.toDouble() ?? 0;
    final stock = (product['stock_quantity'] as num?)?.toInt() ?? 0;
    final available = product['is_available'] as bool? ?? false;
    final imageUrl = product['image_url'] as String?;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Container(
          height: 175,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFF35226E), width: 1.5),
            gradient: imageUrl == null || imageUrl.isEmpty
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF231442), Color(0xFF0F0B1F), Color(0xFF3F1366)],
                  )
                : null,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (imageUrl != null && imageUrl.isNotEmpty) ...[
                Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, _) => const ColoredBox(color: Color(0xFF160F2B)),
                ),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.55),
                        Colors.black.withValues(alpha: 0.92),
                      ],
                    ),
                  ),
                ),
              ],
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(
                              color: available && stock > 0
                                  ? AppColors.green.withValues(alpha: 0.5)
                                  : AppColors.red.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Text(
                            available && stock > 0 ? 'EN STOCK · $stock' : 'RUPTURE DE STOCK',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: available && stock > 0 ? AppColors.green : AppColors.red,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontFamily: 'Orbitron',
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 0.5,
                            shadows: [
                              Shadow(
                                color: Colors.black.withValues(alpha: 0.9),
                                offset: const Offset(0, 2),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                              ),
                              child: Text(
                                '${price.toStringAsFixed(0)} DA',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF00FFCC),
                                  shadows: [
                                    Shadow(
                                      color: Colors.black.withValues(alpha: 0.8),
                                      offset: const Offset(0, 1),
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            _AnimatedOrderButton(
                              onPressed: available && stock > 0 && !_working
                                  ? () => _orderCustomerProduct(product)
                                  : null,
                            ),
                          ],
                        ),
                      ],
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

  Widget _productCard(
    Map<String, dynamic> product, {
    required bool canManageCatalog,
    required bool canManageStock,
  }) {
    final stock = (product['stock_quantity'] as num).toInt();
    final minimum = (product['minimum_stock'] as num).toInt();
    final available = product['is_available'] as bool? ?? false;
    final isLow = stock <= minimum;
    final categoryId = product['category_id'] as String?;
    final category = _categories
        .where((item) => item['id'] == categoryId)
        .firstOrNull;
    final categoryName = category?['name'] as String?;
    final imageUrl = product['image_url'] as String?;
    final statusColor = !available
        ? AppColors.muted
        : isLow
        ? AppColors.red
        : AppColors.green;
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: AppSurface(
        borderRadius: 20,
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: SizedBox(
                    width: 52,
                    height: 52,
                    child: imageUrl == null || imageUrl.isEmpty
                        ? const ColoredBox(
                            color: AppColors.surface2,
                            child: Icon(
                              Icons.inventory_2_rounded,
                              color: AppColors.primaryLight,
                            ),
                          )
                        : Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const ColoredBox(
                              color: AppColors.surface2,
                              child: Icon(
                                Icons.inventory_2_rounded,
                                color: AppColors.primaryLight,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product['name'] as String,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          ?categoryName,
                          'Stock : $stock',
                          '${(product['sale_price'] as num).toStringAsFixed(0)} DA',
                        ].join(' · '),
                        maxLines: 2,
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.muted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        !available
                            ? 'INDISPONIBLE'
                            : isLow
                            ? 'STOCK FAIBLE'
                            : 'EN STOCK',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
                if (canManageCatalog || canManageStock)
                  PopupMenuButton<String>(
                    enabled: !_working,
                    onSelected: (action) {
                      if (action == 'adjust') {
                        _adjustStock(product, isRestock: false);
                      } else if (action == 'toggle') {
                        _toggleAvailability(product);
                      }
                    },
                    itemBuilder: (context) => [
                      if (canManageStock)
                        const PopupMenuItem(
                          value: 'adjust',
                          child: Text('Ajuster / retirer du stock'),
                        ),
                      if (canManageCatalog)
                        PopupMenuItem(
                          value: 'toggle',
                          child: Text(
                            available
                                ? 'Désactiver le produit'
                                : 'Réactiver le produit',
                          ),
                        ),
                    ],
                  ),
                IconButton(
                  tooltip: 'Vendre et encaisser',
                  onPressed: _working || !available || stock == 0
                      ? null
                      : () => _sellProduct(product),
                  icon: const Icon(
                    Icons.point_of_sale_rounded,
                    color: AppColors.pink,
                  ),
                ),
              ],
            ),
            if (canManageStock) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _working
                    ? null
                    : () => _adjustStock(product, isRestock: true),
                icon: const Icon(Icons.add_box_outlined),
                label: const Text('Ajouter au stock'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CustomerSnackCarousel extends StatefulWidget {
  const _CustomerSnackCarousel({required this.products, required this.onOrder});

  final List<Map<String, dynamic>> products;
  final ValueChanged<Map<String, dynamic>> onOrder;

  @override
  State<_CustomerSnackCarousel> createState() => _CustomerSnackCarouselState();
}

class _CustomerSnackCarouselState extends State<_CustomerSnackCarousel> {
  late final PageController _controller;
  Timer? _autoplay;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController(viewportFraction: 0.92);
    _autoplay = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_controller.hasClients) return;
      final available = widget.products
          .where((p) => (p['is_available'] as bool? ?? false) && ((p['stock_quantity'] as num?)?.toInt() ?? 0) > 0)
          .toList();
      if (available.isEmpty) return;
      final next = (_page + 1) % available.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _autoplay?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final available = widget.products
        .where((p) => (p['is_available'] as bool? ?? false) && ((p['stock_quantity'] as num?)?.toInt() ?? 0) > 0)
        .toList();
    if (available.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'SNACKS EN VEDETTE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.2,
              color: AppColors.muted,
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 210,
          child: PageView.builder(
            controller: _controller,
            itemCount: available.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, index) {
              final product = available[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _CustomerSnackBannerCard(
                  product: product,
                  onOrder: () => widget.onOrder(product),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CustomerSnackBannerCard extends StatelessWidget {
  const _CustomerSnackBannerCard({required this.product, required this.onOrder});

  final Map<String, dynamic> product;
  final VoidCallback onOrder;

  @override
  Widget build(BuildContext context) {
    final name = product['name'] as String? ?? 'Produit';
    final price = (product['sale_price'] as num?)?.toDouble() ?? 0;
    final stock = (product['stock_quantity'] as num?)?.toInt() ?? 0;
    final imageUrl = product['image_url'] as String?;

    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: const Color(0xFF35226E), width: 1.5),
          boxShadow: const [
            BoxShadow(
              color: Color(0x664A1C9D),
              offset: Offset(0, 12),
              blurRadius: 28,
              spreadRadius: -6,
            ),
          ],
          gradient: imageUrl == null || imageUrl.isEmpty
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF231442), Color(0xFF0F0B1F), Color(0xFF3F1366)],
                )
              : null,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl != null && imageUrl.isNotEmpty) ...[
              Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF160F2B)),
              ),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.50),
                      Colors.black.withValues(alpha: 0.90),
                    ],
                  ),
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: AppColors.pink.withValues(alpha: 0.5)),
                        ),
                        child: Text(
                          'STOCK : $stock',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: AppColors.pink,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontFamily: 'Orbitron',
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 0.5,
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.9),
                              offset: const Offset(0, 2),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                            ),
                            child: Text(
                              '${price.toStringAsFixed(0)} DA',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF00FFCC),
                                shadows: [
                                  Shadow(
                                    color: Colors.black.withValues(alpha: 0.8),
                                    offset: const Offset(0, 1),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          _AnimatedOrderButton(onPressed: onOrder),
                        ],
                      ),
                    ],
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

class _AnimatedOrderButton extends StatefulWidget {
  const _AnimatedOrderButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  State<_AnimatedOrderButton> createState() => _AnimatedOrderButtonState();
}

class _AnimatedOrderButtonState extends State<_AnimatedOrderButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnim,
      child: FilledButton.icon(
        onPressed: widget.onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.pink,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 8,
          shadowColor: AppColors.pink.withValues(alpha: 0.7),
        ),
        icon: const Icon(Icons.fastfood_rounded, size: 16),
        label: const Text(
          'Commander',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _ProductFormValue {
  const _ProductFormValue({
    required this.name,
    required this.categoryId,
    required this.salePrice,
    required this.costPrice,
    required this.minimumStock,
    required this.imageUrl,
  });

  final String name;
  final String? categoryId;
  final double salePrice;
  final double costPrice;
  final int minimumStock;
  final String imageUrl;
}

class _ProductFormDialog extends StatefulWidget {
  const _ProductFormDialog({required this.categories, required this.venueId});

  final List<Map<String, dynamic>> categories;
  final String venueId;

  @override
  State<_ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends State<_ProductFormDialog> {
  final _name = TextEditingController();
  final _salePrice = TextEditingController();
  final _costPrice = TextEditingController(text: '0');
  final _minimumStock = TextEditingController(text: '5');
  final _imageUrl = TextEditingController();
  String? _categoryId;
  bool _uploadingImage = false;
  String? _imageError;
  late final _imageStorage = CatalogImageStorage(Supabase.instance.client);

  @override
  void dispose() {
    _name.dispose();
    _salePrice.dispose();
    _costPrice.dispose();
    _minimumStock.dispose();
    _imageUrl.dispose();
    super.dispose();
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
      debugPrint('Téléversement de l’image du produit impossible : $error');
      if (mounted) {
        setState(
          () => _imageError =
              'L’image n’a pas pu être envoyée. Vérifiez les droits Storage et réessayez.',
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Téléversement de l’image du produit impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() => _imageError = 'L’image n’a pas pu être envoyée.');
      }
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Ajouter un produit'),
    content: SizedBox(
      width: 400,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nom du produit'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String?>(
              initialValue: _categoryId,
              decoration: const InputDecoration(labelText: 'Catégorie'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Sans catégorie'),
                ),
                ...widget.categories.map(
                  (category) => DropdownMenuItem<String?>(
                    value: category['id'] as String,
                    child: Text(category['name'] as String),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => _categoryId = value),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _salePrice,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Prix de vente',
                suffixText: 'DA',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _costPrice,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Prix de revient',
                suffixText: 'DA',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _minimumStock,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Alerte de stock'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _imageUrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Adresse de l’image (facultatif)',
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _uploadingImage ? null : _pickImage,
                icon: _uploadingImage
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_rounded),
                label: Text(_uploadingImage ? 'Envoi…' : 'Choisir une image'),
              ),
            ),
            if (_imageError != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _imageError!,
                  style: const TextStyle(color: AppColors.red, fontSize: 11),
                ),
              ),
            if (_imageUrl.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Image.network(
                  _imageUrl.text,
                  height: 90,
                  errorBuilder: (_, _, _) => const Text(
                    'Aperçu de l’image indisponible.',
                    style: TextStyle(fontSize: 11, color: AppColors.muted),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            const Text(
              'Le produit est créé avec un stock nul. Ajoutez ensuite une entrée de stock tracée.',
              style: TextStyle(fontSize: 11, color: AppColors.muted),
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
        onPressed: _uploadingImage ? null : _save,
        child: const Text('Créer'),
      ),
    ],
  );

  void _save() {
    final name = _name.text.trim();
    final salePrice = _number(_salePrice.text);
    final costPrice = _number(_costPrice.text);
    final minimumStock = int.tryParse(_minimumStock.text);
    if (name.isEmpty ||
        salePrice == null ||
        salePrice < 0 ||
        costPrice == null ||
        costPrice < 0 ||
        minimumStock == null ||
        minimumStock < 0) {
      return;
    }
    Navigator.pop(
      context,
      _ProductFormValue(
        name: name,
        categoryId: _categoryId,
        salePrice: salePrice,
        costPrice: costPrice,
        minimumStock: minimumStock,
        imageUrl: _imageUrl.text.trim(),
      ),
    );
  }
}

class _RestockProductDialog extends StatelessWidget {
  const _RestockProductDialog({required this.products});

  final List<Map<String, dynamic>> products;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Choisir un produit'),
    content: SizedBox(
      width: 400,
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final product in products)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(product['name'] as String),
              subtitle: Text(
                'Stock actuel : ${(product['stock_quantity'] as num).toInt()}',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.pop(context, product),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
    ],
  );
}

class _StockAdjustmentValue {
  const _StockAdjustmentValue({
    required this.delta,
    required this.reason,
    required this.note,
  });

  final int delta;
  final String reason;
  final String note;
}

class _SaleValue {
  const _SaleValue({required this.quantity, required this.method});

  final int quantity;
  final String method;
}

class _SaleDialog extends StatefulWidget {
  const _SaleDialog({
    required this.productName,
    required this.unitPrice,
    required this.stockQuantity,
  });

  final String productName;
  final double unitPrice;
  final int stockQuantity;

  @override
  State<_SaleDialog> createState() => _SaleDialogState();
}

class _SaleDialogState extends State<_SaleDialog> {
  final _quantity = TextEditingController(text: '1');
  String _method = 'cash';

  @override
  void dispose() {
    _quantity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final quantity = int.tryParse(_quantity.text) ?? 0;
    return AlertDialog(
      title: const Text('Vente au comptoir'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${widget.productName} · ${widget.unitPrice.toStringAsFixed(0)} DA',
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _quantity,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Quantité',
              helperText: 'Stock disponible : ${widget.stockQuantity}',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _method,
            decoration: const InputDecoration(labelText: 'Paiement'),
            items: const [
              DropdownMenuItem(value: 'cash', child: Text('Espèces')),
              DropdownMenuItem(value: 'card', child: Text('Carte')),
              DropdownMenuItem(value: 'wallet', child: Text('Portefeuille')),
              DropdownMenuItem(value: 'credit', child: Text('Crédit (آجل)')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _method = value);
            },
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'Total : ${(widget.unitPrice * quantity).toStringAsFixed(0)} DA',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: quantity > 0 && quantity <= widget.stockQuantity
              ? () => Navigator.pop(
                  context,
                  _SaleValue(quantity: quantity, method: _method),
                )
              : null,
          child: const Text('Encaisser'),
        ),
      ],
    );
  }
}

class _StockAdjustmentDialog extends StatefulWidget {
  const _StockAdjustmentDialog({
    required this.productName,
    required this.currentStock,
    required this.isRestock,
  });

  final String productName;
  final int currentStock;
  final bool isRestock;

  @override
  State<_StockAdjustmentDialog> createState() => _StockAdjustmentDialogState();
}

class _StockAdjustmentDialogState extends State<_StockAdjustmentDialog> {
  final _quantity = TextEditingController(text: '1');
  final _note = TextEditingController();
  String _reason = 'restock';

  @override
  void initState() {
    super.initState();
    if (!widget.isRestock) _reason = 'manual_adjustment';
  }

  @override
  void dispose() {
    _quantity.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.isRestock ? 'Réapprovisionner' : 'Ajuster le stock'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '${widget.productName} · Stock actuel : ${widget.currentStock}',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ),
        if (!widget.isRestock) ...[
          const SizedBox(height: 8),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Pour augmenter le stock, utilisez « Réapprovisionner ». '
              'Cet ajustement retire la quantité indiquée, sauf pour un retour.',
              style: TextStyle(fontSize: 11, color: AppColors.muted),
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _quantity,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Quantité',
            prefixText: widget.isRestock ? '+' : null,
          ),
        ),
        if (!widget.isRestock) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _reason,
            decoration: const InputDecoration(labelText: 'Motif'),
            items: const [
              DropdownMenuItem(
                value: 'manual_adjustment',
                child: Text('Ajustement'),
              ),
              DropdownMenuItem(value: 'damage', child: Text('Produit abîmé')),
              DropdownMenuItem(value: 'correction', child: Text('Correction')),
              DropdownMenuItem(value: 'return', child: Text('Retour')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _reason = value);
            },
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _note,
          maxLength: 500,
          decoration: const InputDecoration(labelText: 'Note (facultative)'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(onPressed: _save, child: const Text('Confirmer')),
    ],
  );

  void _save() {
    final quantity = int.tryParse(_quantity.text);
    if (quantity == null || quantity <= 0) return;
    final reason = widget.isRestock ? 'restock' : _reason;
    final delta = widget.isRestock
        ? quantity
        : reason == 'return'
        ? quantity
        : -quantity;
    Navigator.pop(
      context,
      _StockAdjustmentValue(
        delta: delta,
        reason: reason,
        note: _note.text.trim(),
      ),
    );
  }
}

class _ProductOrderDialog extends StatefulWidget {
  const _ProductOrderDialog({
    required this.name,
    required this.price,
    required this.stock,
    required this.canAddToSession,
  });

  final String name;
  final double price;
  final int stock;
  final bool canAddToSession;

  @override
  State<_ProductOrderDialog> createState() => _ProductOrderDialogState();
}

class _ProductOrderDialogState extends State<_ProductOrderDialog> {
  int _quantity = 1;
  String _paymentMethod = 'cash';

  @override
  Widget build(BuildContext context) {
    final maximum = widget.stock.clamp(1, 100);
    const paymentMethods = [
      {'id': 'cash', 'label': 'Espèces (نقداً)', 'icon': Icons.payments_rounded},
      {'id': 'credit', 'label': 'Crédit / Sur facture (على الأجل)', 'icon': Icons.receipt_long_rounded},
    ];

    return AlertDialog(
      title: const Text('Commander un produit'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 6),
            Text(
              '${widget.price.toStringAsFixed(0)} DA · Stock : ${widget.stock}',
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Diminuer la quantité',
                  onPressed: _quantity > 1
                      ? () => setState(() => _quantity--)
                      : null,
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Text(
                    '$_quantity',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Augmenter la quantité',
                  onPressed: _quantity < maximum
                      ? () => setState(() => _quantity++)
                      : null,
                  icon: const Icon(Icons.add_circle_outline_rounded),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Total : ${(widget.price * _quantity).toStringAsFixed(0)} DA',
              style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primaryLight),
            ),
            const SizedBox(height: 16),
            const Text(
              'Mode de paiement (طريقة الدفع)',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.muted),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _paymentMethod,
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: paymentMethods.map((m) => DropdownMenuItem(
                value: m['id'] as String,
                child: Row(
                  children: [
                    Icon(m['icon'] as IconData, size: 16, color: AppColors.primaryLight),
                    const SizedBox(width: 8),
                    Text(m['label'] as String, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              )).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _paymentMethod = val);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Retour'),
        ),
        if (widget.canAddToSession)
          FilledButton.tonal(
            onPressed: () => Navigator.pop(
              context,
              _ProductOrderSelection(quantity: _quantity, addToSession: true, paymentMethod: _paymentMethod),
            ),
            child: const Text('Ajouter à la session'),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _ProductOrderSelection(quantity: _quantity, addToSession: false, paymentMethod: _paymentMethod),
          ),
          child: const Text('Commander'),
        ),
      ],
    );
  }
}

class _ProductOrderSelection {
  const _ProductOrderSelection({
    required this.quantity,
    required this.addToSession,
    required this.paymentMethod,
  });

  final int quantity;
  final bool addToSession;
  final String paymentMethod;
}

class _InventoryChip extends StatelessWidget {
  const _InventoryChip({
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
      padding: const EdgeInsets.symmetric(horizontal: 15),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: selected ? AppColors.primary : AppColors.surface2,
        border: Border.all(
          color: selected ? AppColors.primaryLight : AppColors.line,
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

class _InventoryNotice extends StatelessWidget {
  const _InventoryNotice({required this.text, required this.onRetry});

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
        IconButton(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, color: AppColors.red),
        ),
      ],
    ),
  );
}

class _InventoryEmpty extends StatelessWidget {
  const _InventoryEmpty();

  @override
  Widget build(BuildContext context) => const AppSurface(
    borderRadius: 20,
    child: Column(
      children: [
        Icon(Icons.inventory_2_outlined, size: 36, color: AppColors.muted),
        SizedBox(height: 12),
        Text(
          'Aucun produit à afficher',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 6),
        Text(
          'Les produits et niveaux de stock de votre salle apparaîtront ici.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppColors.muted),
        ),
      ],
    ),
  );
}

double? _number(String text) =>
    double.tryParse(text.trim().replaceAll(',', '.'));
