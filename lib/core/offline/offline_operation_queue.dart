import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum OfflineQueueState { offline, queued, syncing, syncError, synced }

enum OfflineOperationStatus { queued, syncing, syncError }

class OfflineOperationRecord {
  const OfflineOperationRecord({
    required this.id,
    required this.actorId,
    required this.rpc,
    required this.parameters,
    required this.createdAt,
    required this.attempts,
    required this.status,
    this.errorCode,
  });

  final String id;
  final String actorId;
  final String rpc;
  final Map<String, dynamic> parameters;
  final DateTime createdAt;
  final int attempts;
  final OfflineOperationStatus status;
  final String? errorCode;

  String get label => switch (rpc) {
    'add_product_to_session' ||
    'customer_add_product_to_session' => 'Ajouter un produit à une session',
    'adjust_product_stock' => 'Ajuster le stock',
    'apply_session_promotion' => 'Appliquer une promotion',
    'assign_customer_membership' => 'Attribuer une adhésion',
    'cancel_reservation' => 'Annuler une réservation',
    'close_cash_shift' => 'Clôturer la caisse',
    'create_customer_financial_operation' => 'Mouvement du compte client',
    'create_expense' => 'Enregistrer une dépense',
    'create_request' => 'Demande client',
    'decide_loyalty_redemption' => 'Décider une récompense',
    'open_cash_shift' => 'Ouvrir la caisse',
    'pay_session' => 'Encaisser une session',
    'redeem_loyalty_reward' => 'Demander une récompense',
    'redeem_package_minutes' => 'Utiliser les minutes du forfait',
    'redeem_package_product' => 'Remettre un produit du forfait',
    'reserve_post' => 'Réserver un poste',
    'sell_customer_package' => 'Vendre un forfait',
    'sell_product' => 'Vendre un produit',
    'set_reservation_status' => 'Modifier une réservation',
    'staff_reserve_post' => 'Réserver un poste pour un client',
    'start_session' => 'Démarrer une session',
    'transfer_session' => 'Transférer une session',
    _ => 'Synchroniser une opération',
  };

  String? get statusMessage => switch (status) {
    OfflineOperationStatus.queued => 'En attente de connexion.',
    OfflineOperationStatus.syncing => 'Synchronisation en cours.',
    OfflineOperationStatus.syncError =>
      'Le serveur a refusé cette opération. Vérifiez la situation avant de la supprimer ou de réessayer.',
  };

  Map<String, Object?> toMap() => {
    'id': id,
    'actor_id': actorId,
    'rpc': rpc,
    'parameters': parameters,
    'created_at': createdAt.toUtc().toIso8601String(),
    'attempts': attempts,
    'status': status.name,
    'error_code': errorCode,
  };

  factory OfflineOperationRecord.fromMap(Map<dynamic, dynamic> map) {
    final statusName = map['status'] as String? ?? '';
    final status = OfflineOperationStatus.values.firstWhere(
      (value) => value.name == statusName,
      orElse: () => OfflineOperationStatus.queued,
    );
    final createdAt = DateTime.tryParse(map['created_at'] as String? ?? '');
    if (createdAt == null) {
      throw const FormatException('Invalid offline operation timestamp');
    }
    final rawParameters = map['parameters'];
    if (rawParameters is! Map) {
      throw const FormatException('Invalid offline operation parameters');
    }
    return OfflineOperationRecord(
      id: map['id'] as String,
      actorId: map['actor_id'] as String,
      rpc: map['rpc'] as String,
      parameters: Map<String, dynamic>.from(rawParameters),
      createdAt: createdAt,
      attempts: (map['attempts'] as num?)?.toInt() ?? 0,
      status: status,
      errorCode: map['error_code'] as String?,
    );
  }
}

class PendingOfflineOperationException implements Exception {
  const PendingOfflineOperationException(this.operationId);

  final String operationId;
}

class OfflineOperationQueue extends ChangeNotifier with WidgetsBindingObserver {
  OfflineOperationQueue._({
    required Box<dynamic> box,
    required String? Function() currentActor,
    required Future<Object?> Function(
      String rpc,
      Map<String, dynamic> parameters,
    )
    dispatchRpc,
    required bool initiallyOnline,
    Connectivity? connectivity,
    Stream<bool>? connectivityChanges,
    Stream<AuthState>? authChanges,
  }) : _box = box,
       _currentActor = currentActor,
       _dispatchRpc = dispatchRpc,
       _online = initiallyOnline,
       _connectivity = connectivity,
       _connectivityChanges = connectivityChanges,
       _authChanges = authChanges;

  static const _boxName = 'ghost_gaming_offline_operations';
  static const _encryptionKeyName = 'ghost_gaming_offline_queue_key';
  static OfflineOperationQueue? _instance;

  static OfflineOperationQueue get instance =>
      _instance ??
      (throw StateError('Offline operation queue has not been initialized'));

  static Future<void> initialize(SupabaseClient client) async {
    if (_instance != null) return;
    await Hive.initFlutter();
    final secureStorage = FlutterSecureStorage();
    var encodedKey = await secureStorage.read(key: _encryptionKeyName);
    if (encodedKey == null) {
      encodedKey = base64Encode(Hive.generateSecureKey());
      await secureStorage.write(key: _encryptionKeyName, value: encodedKey);
    }
    final encryptionKey = base64Decode(encodedKey);
    if (encryptionKey.length != 32) {
      throw const FormatException('Invalid offline queue encryption key');
    }
    final box = await Hive.openBox<dynamic>(
      _boxName,
      encryptionCipher: HiveAesCipher(encryptionKey),
    );
    final queue = OfflineOperationQueue._(
      box: box,
      currentActor: () => client.auth.currentUser?.id,
      dispatchRpc: (rpc, parameters) => client.rpc(rpc, params: parameters),
      initiallyOnline: true,
      connectivity: Connectivity(),
      authChanges: client.auth.onAuthStateChange,
    );
    await queue._start();
    _instance = queue;
  }

  final Box<dynamic> _box;
  final String? Function() _currentActor;
  final Future<Object?> Function(String, Map<String, dynamic>) _dispatchRpc;
  final Connectivity? _connectivity;
  final Stream<bool>? _connectivityChanges;
  final Stream<AuthState>? _authChanges;
  final Map<String, Object?> _completedResults = {};
  final Set<String> _awaitingResults = {};
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<bool>? _testConnectivitySubscription;
  Future<void> _operationLock = Future<void>.value();
  bool _online = false;
  bool _syncing = false;
  bool _observingLifecycle = false;

  List<OfflineOperationRecord> get operations {
    final actorId = _currentActor();
    if (actorId == null) return const [];
    final records = _box.values
        .map(
          (value) => OfflineOperationRecord.fromMap(
            Map<dynamic, dynamic>.from(value as Map),
          ),
        )
        .where((record) => record.actorId == actorId)
        .toList();
    records.sort((a, b) {
      final byCreation = a.createdAt.compareTo(b.createdAt);
      return byCreation == 0 ? a.id.compareTo(b.id) : byCreation;
    });
    return List.unmodifiable(records);
  }

  OfflineQueueState get state {
    if (!_online) return OfflineQueueState.offline;
    if (_syncing) return OfflineQueueState.syncing;
    return operations.isEmpty
        ? OfflineQueueState.synced
        : OfflineQueueState.queued;
  }

  Future<void> _start() async {
    if (_connectivity != null) {
      WidgetsBinding.instance.addObserver(this);
      _observingLifecycle = true;
    }
    for (final key in _box.keys.toList()) {
      final raw = _box.get(key);
      if (raw is Map && raw['status'] == OfflineOperationStatus.syncing.name) {
        await _updateStatus(key as String, OfflineOperationStatus.queued);
      }
    }
    if (_connectivity != null) {
      _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
        (results) => _setOnline(
          results.any((result) => result != ConnectivityResult.none),
        ),
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('Suivi réseau impossible : $error');
          debugPrintStack(stackTrace: stackTrace);
          _setOnline(false);
        },
      );
      try {
        final results = await _connectivity.checkConnectivity();
        _setOnline(results.any((result) => result != ConnectivityResult.none));
      } catch (error, stackTrace) {
        debugPrint('État réseau initial indisponible : $error');
        debugPrintStack(stackTrace: stackTrace);
        _online = false;
        notifyListeners();
      }
    }
    if (_connectivityChanges != null) {
      _testConnectivitySubscription = _connectivityChanges.listen(_setOnline);
    }
    _authSubscription = _authChanges?.listen((_) {
      notifyListeners();
      if (_online) unawaited(synchronize());
    });
  }

  Future<T> executeRpc<T>({
    required String actorId,
    required String rpc,
    required Map<String, dynamic> parameters,
  }) async {
    if (actorId.isEmpty || _currentActor() != actorId) {
      throw const AuthException('UNAUTHENTICATED');
    }
    final operationId = parameters['p_op'];
    if (operationId is! String || operationId.isEmpty) {
      throw ArgumentError.value(
        parameters['p_op'],
        'parameters[p_op]',
        'A durable operation UUID is required.',
      );
    }

    final existing = _box.get(operationId);
    if (existing != null) {
      throw StateError('Operation ID is already queued: $operationId');
    }

    final record = OfflineOperationRecord(
      id: operationId,
      actorId: actorId,
      rpc: rpc,
      parameters: Map<String, dynamic>.unmodifiable(parameters),
      createdAt: DateTime.now().toUtc(),
      attempts: 0,
      status: OfflineOperationStatus.queued,
    );
    _awaitingResults.add(operationId);
    await _box.put(operationId, record.toMap());
    notifyListeners();

    if (!_online) {
      _awaitingResults.remove(operationId);
      throw PendingOfflineOperationException(operationId);
    }
    try {
      await _runExclusive(() => _drain(actorId, untilOperationId: operationId));
    } on PostgrestException {
      _awaitingResults.remove(operationId);
      rethrow;
    } on AuthException {
      _awaitingResults.remove(operationId);
      rethrow;
    } on PendingOfflineOperationException {
      _awaitingResults.remove(operationId);
      rethrow;
    }
    if (_completedResults.containsKey(operationId)) {
      _awaitingResults.remove(operationId);
      return _completedResults.remove(operationId) as T;
    }
    _awaitingResults.remove(operationId);
    throw PendingOfflineOperationException(operationId);
  }

  Future<void> synchronize() async {
    final actorId = _currentActor();
    if (!_online || actorId == null) return;
    await _runExclusive(() => _drain(actorId));
  }

  Future<void> retry(String operationId) async {
    final operation = _record(operationId);
    if (operation == null ||
        operation.actorId != _currentActor() ||
        operation.status != OfflineOperationStatus.syncError) {
      throw StateError('This offline operation cannot be retried.');
    }
    await _updateStatus(operationId, OfflineOperationStatus.queued);
    await synchronize();
  }

  Future<void> discardRejected(String operationId) async {
    final operation = _record(operationId);
    if (operation == null ||
        operation.actorId != _currentActor() ||
        operation.status != OfflineOperationStatus.syncError) {
      throw StateError('Only a rejected operation can be discarded.');
    }
    await _box.delete(operationId);
    notifyListeners();
    await synchronize();
  }

  Future<void> _drain(String actorId, {String? untilOperationId}) async {
    if (!_online || _currentActor() != actorId) return;
    _syncing = true;
    notifyListeners();
    try {
      for (final operation in operations) {
        if (operation.actorId != actorId) continue;
        if (_currentActor() != actorId) return;
        if (operation.status == OfflineOperationStatus.syncError) continue;
        final record = operation.status == OfflineOperationStatus.syncing
            ? await _updateStatus(operation.id, OfflineOperationStatus.queued)
            : operation;
        final syncing = await _replace(
          record,
          status: OfflineOperationStatus.syncing,
          attempts: record.attempts + 1,
          errorCode: null,
        );
        try {
          final result = await _dispatchRpc(syncing.rpc, syncing.parameters);
          if (_awaitingResults.contains(syncing.id)) {
            _completedResults[syncing.id] = result;
          }
          await _box.delete(syncing.id);
          notifyListeners();
        } on PostgrestException catch (error, stackTrace) {
          await _box.delete(syncing.id);
          notifyListeners();
          if (syncing.id == untilOperationId) {
            Error.throwWithStackTrace(error, stackTrace);
          }
        } on AuthException catch (error, stackTrace) {
          await _replace(
            syncing,
            status: OfflineOperationStatus.queued,
            attempts: syncing.attempts,
            errorCode: 'AUTH_REQUIRED',
          );
          if (syncing.id == untilOperationId) {
            Error.throwWithStackTrace(error, stackTrace);
          }
          return;
        } catch (error, stackTrace) {
          final isTransient = _looksLikeNetworkFailure(error);
          if (isTransient) {
            await _replace(
              syncing,
              status: OfflineOperationStatus.queued,
              attempts: syncing.attempts,
              errorCode: null,
            );
            debugPrint('Opération conservée pour une nouvelle tentative.');
          } else {
            await _box.delete(syncing.id);
            notifyListeners();
            debugPrint('Échec de synchronisation de ${syncing.rpc}: $error');
            debugPrintStack(stackTrace: stackTrace);
          }
          if (syncing.id == untilOperationId) {
            if (isTransient) {
              throw PendingOfflineOperationException(syncing.id);
            } else {
              rethrow;
            }
          }
        }
        if (syncing.id == untilOperationId) return;
      }
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  Future<T> _runExclusive<T>(Future<T> Function() action) async {
    final previous = _operationLock;
    final release = Completer<void>();
    _operationLock = release.future;
    await previous;
    try {
      return await action();
    } finally {
      release.complete();
    }
  }

  Future<OfflineOperationRecord> _updateStatus(
    String id,
    OfflineOperationStatus status,
  ) async {
    final record = _record(id);
    if (record == null) throw StateError('Queued operation disappeared.');
    return _replace(record, status: status);
  }

  Future<OfflineOperationRecord> _replace(
    OfflineOperationRecord record, {
    OfflineOperationStatus? status,
    int? attempts,
    String? errorCode,
  }) async {
    final updated = OfflineOperationRecord(
      id: record.id,
      actorId: record.actorId,
      rpc: record.rpc,
      parameters: record.parameters,
      createdAt: record.createdAt,
      attempts: attempts ?? record.attempts,
      status: status ?? record.status,
      errorCode: errorCode,
    );
    await _box.put(updated.id, updated.toMap());
    notifyListeners();
    return updated;
  }

  OfflineOperationRecord? _record(String id) {
    final raw = _box.get(id);
    return raw is Map
        ? OfflineOperationRecord.fromMap(Map<dynamic, dynamic>.from(raw))
        : null;
  }

  void _setOnline(bool online) {
    _online = online;
    notifyListeners();
    if (_online) unawaited(synchronize());
  }

  bool _looksLikeNetworkFailure(Object error) {
    if (error is TimeoutException) return true;
    final message = error.toString().toLowerCase();
    return message.contains('socketexception') ||
        message.contains('clientexception') ||
        message.contains('failed host lookup') ||
        message.contains('failed to fetch') ||
        message.contains('connection refused') ||
        message.contains('network is unreachable') ||
        message.contains('connection reset');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(synchronize());
  }

  @override
  void dispose() {
    if (_observingLifecycle) WidgetsBinding.instance.removeObserver(this);
    unawaited(_connectivitySubscription?.cancel());
    unawaited(_authSubscription?.cancel());
    unawaited(_testConnectivitySubscription?.cancel());
    super.dispose();
  }

  @visibleForTesting
  factory OfflineOperationQueue.forTesting({
    required Box<dynamic> box,
    required String? Function() currentActor,
    required Future<Object?> Function(
      String rpc,
      Map<String, dynamic> parameters,
    )
    dispatchRpc,
    required bool initiallyOnline,
    required Stream<bool> connectivityChanges,
  }) {
    final queue = OfflineOperationQueue._(
      box: box,
      currentActor: currentActor,
      dispatchRpc: dispatchRpc,
      initiallyOnline: initiallyOnline,
      connectivityChanges: connectivityChanges,
    );
    unawaited(queue._start());
    return queue;
  }
}

Future<T> executeIdempotentRpc<T>(
  SupabaseClient client,
  String rpc,
  Map<String, dynamic> parameters,
) {
  final actorId = client.auth.currentUser?.id;
  if (actorId == null) throw const AuthException('UNAUTHENTICATED');
  return OfflineOperationQueue.instance.executeRpc<T>(
    actorId: actorId,
    rpc: rpc,
    parameters: parameters,
  );
}
