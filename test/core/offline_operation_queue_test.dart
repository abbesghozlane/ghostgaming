import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghostgaming/core/offline/offline_operation_queue.dart';
import 'package:hive_ce/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late Directory directory;
  late Box<dynamic> box;
  final controllers = <StreamController<bool>>[];
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ghost-offline-');
    Hive.init(directory.path);
    box = await Hive.openBox<dynamic>('test-operations');
  });

  tearDown(() async {
    for (final queue in _activeQueues) {
      queue.dispose();
    }
    _activeQueues.clear();
    for (final controller in controllers) {
      await controller.close();
    }
    controllers.clear();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('persists offline work and retries it with its original id', () async {
    final changes = StreamController<bool>.broadcast();
    controllers.add(changes);
    final dispatched = Completer<void>();
    final sentIds = <String>[];
    final queue = _queue(
      changes: changes,
      initiallyOnline: false,
      dispatch: (rpc, parameters) async {
        expect(rpc, 'sell_product');
        sentIds.add(parameters['p_op'] as String);
        dispatched.complete();
        return {'invoice_number': 17};
      },
    );

    await expectLater(
      queue.executeRpc<Object?>(
        actorId: 'user-1',
        rpc: 'sell_product',
        parameters: {'p_op': 'op-1', 'p_quantity': 2},
      ),
      throwsA(isA<PendingOfflineOperationException>()),
    );
    expect(queue.operations.single.status, OfflineOperationStatus.queued);
    expect(queue.state, OfflineQueueState.offline);

    changes.add(true);
    await dispatched.future;
    await _waitUntil(() => queue.state == OfflineQueueState.synced);

    expect(sentIds, ['op-1']);
  });

  test('automatically discards rejected work on server error', () async {
    final changes = StreamController<bool>.broadcast();
    controllers.add(changes);
    final firstAttempt = Completer<void>();
    final queue = _queue(
      changes: changes,
      initiallyOnline: false,
      dispatch: (rpc, parameters) async {
        firstAttempt.complete();
        throw const PostgrestException(
          message: 'RESERVATION_SLOT_TAKEN',
          code: '23P01',
        );
      },
    );

    await expectLater(
      queue.executeRpc<void>(
        actorId: 'user-1',
        rpc: 'reserve_post',
        parameters: {'p_op': 'op-2', 'p_post': 'post-1'},
      ),
      throwsA(isA<PendingOfflineOperationException>()),
    );
    changes.add(true);
    await firstAttempt.future;
    await _waitUntil(
      () => queue.state == OfflineQueueState.synced,
    );
    expect(queue.operations, isEmpty);
    expect(queue.state, OfflineQueueState.synced);
  });

  test('restores queued operations from disk after reopening Hive', () async {
    final changes = StreamController<bool>.broadcast();
    controllers.add(changes);
    final queue = _queue(
      changes: changes,
      initiallyOnline: false,
      dispatch: (rpc, parameters) async => null,
    );

    await expectLater(
      queue.executeRpc<void>(
        actorId: 'user-1',
        rpc: 'sell_product',
        parameters: {'p_op': 'op-persisted', 'p_product': 'product-1'},
      ),
      throwsA(isA<PendingOfflineOperationException>()),
    );

    queue.dispose();
    _activeQueues.remove(queue);
    await Hive.close();
    Hive.init(directory.path);
    box = await Hive.openBox<dynamic>('test-operations');

    final restored = OfflineOperationRecord.fromMap(
      Map<dynamic, dynamic>.from(box.get('op-persisted') as Map),
    );
    expect(restored.actorId, 'user-1');
    expect(restored.parameters['p_op'], 'op-persisted');
    expect(restored.status, OfflineOperationStatus.queued);
  });

  test('never dispatches another account’s persisted operation', () async {
    var actorId = 'user-2';
    var dispatches = 0;
    final oldOperation = OfflineOperationRecord(
      id: 'op-old-account',
      actorId: 'user-1',
      rpc: 'sell_product',
      parameters: const {'p_op': 'op-old-account'},
      createdAt: DateTime.utc(2026),
      attempts: 0,
      status: OfflineOperationStatus.queued,
    );
    await box.put(oldOperation.id, oldOperation.toMap());
    final changes = StreamController<bool>.broadcast();
    controllers.add(changes);
    final queue = _queue(
      changes: changes,
      initiallyOnline: true,
      currentActor: () => actorId,
      dispatch: (rpc, parameters) async {
        dispatches++;
        return null;
      },
    );

    await Future<void>.delayed(Duration.zero);
    expect(queue.operations, isEmpty);
    expect(dispatches, 0);

    actorId = 'user-1';
    await queue.synchronize();

    expect(dispatches, 1);
    expect(queue.operations, isEmpty);
  });
}

OfflineOperationQueue _queue({
  required StreamController<bool> changes,
  required bool initiallyOnline,
  required Future<Object?> Function(String rpc, Map<String, dynamic> parameters)
  dispatch,
  String? Function()? currentActor,
}) {
  final queue = OfflineOperationQueue.forTesting(
    box: Hive.box<dynamic>('test-operations'),
    currentActor: currentActor ?? () => 'user-1',
    dispatchRpc: dispatch,
    initiallyOnline: initiallyOnline,
    connectivityChanges: changes.stream,
  );
  _activeQueues.add(queue);
  return queue;
}

final _activeQueues = <OfflineOperationQueue>[];

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Condition was not met before timeout.');
}
