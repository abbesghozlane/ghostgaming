import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/app_widgets.dart';
import '../data/notification_repository.dart';

class NotificationInboxScreen extends StatefulWidget {
  const NotificationInboxScreen({super.key});

  @override
  State<NotificationInboxScreen> createState() =>
      _NotificationInboxScreenState();
}

class _NotificationInboxScreenState extends State<NotificationInboxScreen> {
  late final NotificationRepository _repository;
  final String? _userId = Supabase.instance.client.auth.currentUser?.id;
  List<AppNotification> _items = const [];
  RealtimeChannel? _channel;
  Timer? _reloadTimer;
  String? _error;
  bool _loading = true;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _repository = NotificationRepository(Supabase.instance.client);
    _load();
    final userId = _userId;
    if (userId != null) {
      _channel = _repository.subscribe(
        userId,
        onChange: _scheduleReload,
        onError: () {
          if (mounted) {
            setState(
              () => _error =
                  'La synchronisation des notifications est interrompue.',
            );
          }
        },
      );
    }
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _reloadTimer?.cancel();
    super.dispose();
  }

  void _scheduleReload() {
    _reloadTimer?.cancel();
    _reloadTimer = Timer(const Duration(milliseconds: 250), _load);
  }

  Future<void> _load() async {
    try {
      final items = await _repository.load();
      if (!mounted) return;
      setState(() {
        _items = items;
        _error = null;
        _loading = false;
      });
    } on PostgrestException catch (error) {
      debugPrint('Chargement des notifications impossible : $error');
      if (mounted) {
        setState(() {
          _error = 'Les notifications n’ont pas pu être chargées.';
          _loading = false;
        });
      }
    } catch (error, stackTrace) {
      debugPrint('Chargement des notifications impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _error = 'Les notifications n’ont pas pu être chargées.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _markAllRead() async {
    if (_working || !_items.any((item) => !item.isRead)) return;
    setState(() => _working = true);
    try {
      await _repository.markAllRead();
      await _load();
    } on PostgrestException catch (error) {
      debugPrint('Lecture des notifications impossible : $error');
      if (mounted) setState(() => _error = 'La mise à jour a échoué.');
    } catch (error, stackTrace) {
      debugPrint('Lecture des notifications impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) setState(() => _error = 'La mise à jour a échoué.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _open(AppNotification item) async {
    if (!item.isRead) {
      try {
        await _repository.markRead(item.id);
      } on PostgrestException catch (error) {
        debugPrint('Lecture de la notification impossible : $error');
        if (mounted) {
          setState(() => _error = 'La notification n’a pas été lue.');
        }
        return;
      } catch (error, stackTrace) {
        debugPrint('Lecture de la notification impossible : $error');
        debugPrintStack(stackTrace: stackTrace);
        if (mounted) {
          setState(() => _error = 'La notification n’a pas été lue.');
        }
        return;
      }
      if (mounted) {
        setState(() {
          _items = [
            for (final current in _items)
              if (current.id == item.id)
                AppNotification(
                  id: current.id,
                  type: current.type,
                  title: current.title,
                  body: current.body,
                  referenceType: current.referenceType,
                  referenceId: current.referenceId,
                  data: current.data,
                  isRead: true,
                  createdAt: current.createdAt,
                )
              else
                current,
          ];
        });
      }
    }

    if (!mounted) return;
    final role = await _currentRole();
    if (!mounted) return;
    context.go(item.destinationForRole(role));
  }

  Future<String?> _currentRole() async {
    try {
      final membership = await Supabase.instance.client
          .from('venue_members')
          .select('role')
          .eq('user_id', _userId ?? '')
          .eq('is_active', true)
          .order('created_at')
          .limit(1)
          .maybeSingle();
      return membership?['role'] as String?;
    } on PostgrestException catch (error) {
      debugPrint('Vérification du rôle impossible : $error');
      return null;
    }
  }

  Future<void> _goBack() async {
    if (context.canPop()) {
      context.pop();
      return;
    }
    final role = await _currentRole();
    if (!mounted) return;
    context.go(role == 'customer' ? '/customer/home' : '/home');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 30),
            children: [
              AppScreenTitle(
                title: 'Notifications',
                subtitle: 'Vos mises à jour et demandes récentes',
                trailing: IconButton(
                  tooltip: 'Retour',
                  onPressed: _goBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
              ),
              if (_items.any((item) => !item.isRead))
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _working ? null : _markAllRead,
                    child: const Text('Tout marquer comme lu'),
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: AppSurface(
                    borderRadius: 16,
                    child: Text(
                      _error!,
                      style: const TextStyle(color: AppColors.red),
                    ),
                  ),
                ),
              if (_loading && _items.isEmpty)
                const SizedBox(
                  height: 220,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_items.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: AppSurface(
                    borderRadius: 20,
                    child: Text(
                      'Vous n’avez aucune notification.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                ..._items.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(top: 9),
                    child: AppSurface(
                      borderRadius: 18,
                      onTap: () => _open(item),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            item.isRead
                                ? Icons.notifications_none_rounded
                                : Icons.notifications_active_rounded,
                            color: item.isRead
                                ? AppColors.muted
                                : AppColors.pink,
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (item.body?.isNotEmpty == true) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    item.body!,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.muted,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 5),
                                Text(
                                  _dateLabel(item.createdAt),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
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
      ),
    );
  }

  String _dateLabel(DateTime value) =>
      DateFormat('dd MMMM yyyy · HH:mm', 'fr_FR').format(value);
}
