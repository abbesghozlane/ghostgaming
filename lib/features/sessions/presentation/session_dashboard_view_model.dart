import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/session_dashboard_repository.dart';
import '../domain/session_dashboard_models.dart';

class SessionDashboardViewModel extends ChangeNotifier {
  SessionDashboardViewModel(this._repository);

  final SessionDashboardRepository _repository;
  SessionDashboardSnapshot? snapshot;
  String? errorMessage;
  bool isLoading = true;
  bool isWorking = false;
  RealtimeChannel? _sessionsChannel;
  RealtimeChannel? _postsChannel;
  RealtimeChannel? _catalogChannel;
  RealtimeChannel? _requestsChannel;
  RealtimeChannel? _inventoryChannel;
  RealtimeChannel? _customersChannel;
  RealtimeChannel? _promotionsChannel;
  Timer? _refreshDebounce;
  bool _disposed = false;

  Future<void> initialize() async {
    await refresh();
  }

  Future<void> refresh() async {
    if (_disposed) return;
    try {
      final nextSnapshot = await _repository.load();
      if (_disposed) return;
      final venueChanged = snapshot?.venueId != nextSnapshot.venueId;
      snapshot = nextSnapshot;
      errorMessage = null;
      if (venueChanged) _subscribe(nextSnapshot.venueId);
    } on SessionDashboardException catch (error) {
      if (!_disposed) errorMessage = error.message;
    } on PostgrestException {
      if (!_disposed) {
        errorMessage =
            'Les données n’ont pas pu être chargées. Vérifiez votre connexion.';
      }
    } catch (error, stackTrace) {
      debugPrint('Chargement du tableau de bord impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!_disposed) {
        errorMessage =
            'Les données n’ont pas pu être chargées. Réessayez dans quelques instants.';
      }
    } finally {
      if (!_disposed) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  void _subscribe(String venueId) {
    _sessionsChannel?.unsubscribe();
    _postsChannel?.unsubscribe();
    _catalogChannel?.unsubscribe();
    _requestsChannel?.unsubscribe();
    _inventoryChannel?.unsubscribe();
    _customersChannel?.unsubscribe();
    _promotionsChannel?.unsubscribe();
    _sessionsChannel = _repository.subscribeToVenue(
      venueId,
      onChange: _scheduleRefresh,
      onError: _scheduleRefresh,
    );
    _postsChannel = _repository.subscribeToPosts(
      venueId,
      onChange: _scheduleRefresh,
      onError: _scheduleRefresh,
    );
    _catalogChannel = _repository.subscribeToCatalog(
      venueId,
      onChange: _scheduleRefresh,
      onError: _scheduleRefresh,
    );
    _requestsChannel = _repository.subscribeToRequests(
      venueId,
      onChange: _scheduleRefresh,
      onError: _scheduleRefresh,
    );
    _inventoryChannel = _repository.subscribeToInventory(
      venueId,
      onChange: _scheduleRefresh,
      onError: _scheduleRefresh,
    );
    _customersChannel = _repository.subscribeToCustomers(
      venueId,
      onChange: _scheduleRefresh,
      onError: _scheduleRefresh,
    );
    _promotionsChannel = _repository.subscribeToPromotions(
      venueId,
      onChange: _scheduleRefresh,
      onError: _scheduleRefresh,
    );
  }

  void _scheduleRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 250), refresh);
  }

  Future<void> startSession({
    required GamingPost post,
    required CatalogGame game,
    int? initialMinutes,
    String? customerId,
  }) async {
    await _perform(() async {
      await _repository.call('start_session', {
        'p_post': post.id,
        'p_game': game.id,
        'p_customer': customerId,
        'p_initial_minutes': initialMinutes,
      });
    });
  }

  Future<void> transferSession(
    ActiveGamingSession session,
    GamingPost newPost,
  ) async {
    await _perform(() async {
      await _repository.call('transfer_session', {
        'p_session': session.id,
        'p_new_post': newPost.id,
      });
    });
  }

  Future<void> runSessionAction(
    ActiveGamingSession session,
    String action, {
    int? quantity,
    int? minutes,
  }) async {
    await _perform(() async {
      switch (action) {
        case 'add_match':
          await _repository.call('add_match', {
            'p_session': session.id,
            'p_qty': quantity ?? 1,
          });
        case 'add_time':
          await _repository.call('add_time', {
            'p_session': session.id,
            'p_minutes': minutes,
          });
        case 'pause_session':
        case 'resume_session':
        case 'end_session':
          await _repository.call(action, {'p_session': session.id});
      }
    });
  }

  Future<void> decideRequest(
    PendingSessionRequest request, {
    required bool approve,
  }) async {
    await _perform(() async {
      await _repository.call('decide_request', {
        'p_request': request.id,
        'p_approve': approve,
      });
    });
  }

  Future<Map<String, dynamic>?> processStandaloneOrder(
    PendingStandaloneOrderRequest request, {
    required bool complete,
    String? paymentMethod,
  }) async {
    Map<String, dynamic>? result;
    await _perform(() async {
      result = await _repository.call('process_standalone_order_request', {
        'p_request': request.id,
        'p_complete': complete,
        'p_method': paymentMethod,
      });
    });
    return result;
  }

  Future<void> addProductToSession(
    ActiveGamingSession session,
    SessionProduct product,
    int quantity,
  ) async {
    await _perform(() async {
      await _repository.call('add_product_to_session', {
        'p_session': session.id,
        'p_product': product.id,
        'p_quantity': quantity,
      });
    });
  }

  Future<Map<String, dynamic>?> paySession(
    ActiveGamingSession session,
    List<Map<String, dynamic>> lines, {
    String? customerId,
  }) async {
    Map<String, dynamic>? result;
    await _perform(() async {
      final params = <String, dynamic>{
        'p_session': session.id,
        'p_lines': lines,
      };
      if (customerId != null) {
        params['p_customer_id'] = customerId;
      }
      result = await _repository.call('pay_session', params);
    });
    return result;
  }

  Future<Map<String, dynamic>?> applyPromotion(
    ActiveGamingSession session,
    SessionPromotion promotion,
  ) async {
    Map<String, dynamic>? result;
    await _perform(() async {
      result = await _repository.applyPromotion(session.id, promotion.id);
    });
    return result;
  }

  Future<List<Map<String, dynamic>>> loadSessionOrderItems(String sessionId) {
    return _repository.loadSessionOrderItems(sessionId);
  }

  Future<void> _perform(Future<void> Function() operation) async {
    if (isWorking) return;
    isWorking = true;
    errorMessage = null;
    notifyListeners();
    try {
      await operation();
      await refresh();
    } on SessionDashboardException catch (error) {
      errorMessage = error.message;
      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint('Opération de session impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      errorMessage =
          'L’opération a échoué. Vérifiez la connexion puis réessayez.';
      notifyListeners();
    } finally {
      isWorking = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshDebounce?.cancel();
    _sessionsChannel?.unsubscribe();
    _postsChannel?.unsubscribe();
    _catalogChannel?.unsubscribe();
    _requestsChannel?.unsubscribe();
    _inventoryChannel?.unsubscribe();
    _customersChannel?.unsubscribe();
    _promotionsChannel?.unsubscribe();
    super.dispose();
  }
}
