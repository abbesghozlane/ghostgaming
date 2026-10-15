import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/app_bottom_nav.dart';
import '../../../app/widgets/app_widgets.dart';
import '../../../core/data/current_role_cache.dart';
import '../../../core/utils/venue_time_zone.dart';
import '../data/reservation_repository.dart';

class BookingScreen extends StatefulWidget {
  const BookingScreen({super.key});

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  late final ReservationRepository _repository;
  ReservationSnapshot? _snapshot;
  RealtimeChannel? _channel;
  Timer? _refreshTimer;
  DateTime _startsAt = _defaultStart('Africa/Algiers');
  String? _postId;
  String? _customerId;
  int _duration = 60;
  String? _error;
  bool _loading = true;
  bool _working = false;
  bool _reservationJumpScheduled = false;
  final _reservationTargetKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _repository = ReservationRepository(Supabase.instance.client);
    _load();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _refreshTimer?.cancel();
    super.dispose();
  }

  static DateTime _defaultStart(String timeZone) {
    final now = VenueTimeZone.now(timeZone);
    final roundedHour = VenueTimeZone.dateTime(
      timeZone,
      year: now.year,
      month: now.month,
      day: now.day,
      hour: now.hour + 1,
    );
    return roundedHour.isAfter(now)
        ? roundedHour
        : roundedHour.add(const Duration(hours: 1));
  }

  Future<void> _load() async {
    try {
      final snapshot = await _repository.load();
      if (!mounted) return;
      final venueChanged = _snapshot?.venue.id != snapshot.venue.id;
      setState(() {
        if (_snapshot == null || venueChanged) {
          _startsAt = _defaultStart(snapshot.venue.timeZone);
        }
        _snapshot = snapshot;
        _error = null;
        _loading = false;
        if (_postId == null ||
            !snapshot.posts.any((post) => post['id'] == _postId)) {
          _postId = snapshot.posts.isEmpty
              ? null
              : snapshot.posts.first['id'] as String;
        }
        if (_customerId == null ||
            !snapshot.customers.any((customer) => customer.id == _customerId)) {
          _customerId = snapshot.customers.isEmpty
              ? null
              : snapshot.customers.first.id;
        }
      });
      if (venueChanged) _subscribe(snapshot);
    } on PostgrestException catch (error) {
      if (mounted) {
        setState(() {
          _error = reservationErrorMessage(error.message);
          _loading = false;
        });
      }
    } catch (error, stackTrace) {
      debugPrint('Chargement des réservations impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _error = 'Les réservations n’ont pas pu être chargées.';
          _loading = false;
        });
      }
    }
  }

  void _subscribe(ReservationSnapshot snapshot) {
    _channel?.unsubscribe();
    final client = Supabase.instance.client;
    if (snapshot.isStaff) {
      _channel = client.channel('venue:${snapshot.venue.id}:reservations');
      _channel!.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'reservations',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'venue_id',
          value: snapshot.venue.id,
        ),
        callback: (_) => _scheduleReload(),
      );
      _channel!.subscribe((status, error) {
        if ((status == RealtimeSubscribeStatus.channelError ||
                status == RealtimeSubscribeStatus.timedOut) &&
            mounted) {
          setState(
            () => _error =
                'La synchronisation des réservations est interrompue. Actualisez pour réessayer.',
          );
        }
      });
    } else {
      final userId = client.auth.currentUser?.id;
      if (userId == null) return;
      _channel = client.channel('user:$userId');
      _channel!.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'reservations',
        callback: (_) => _scheduleReload(),
      );
      _channel!.subscribe();
    }
  }

  void _scheduleReload() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(const Duration(milliseconds: 300), _load);
  }

  Future<void> _chooseDate() async {
    final timeZone = _snapshot?.venue.timeZone ?? 'Africa/Algiers';
    final now = VenueTimeZone.now(timeZone);
    final date = await showDatePicker(
      context: context,
      initialDate: _startsAt,
      firstDate: now,
      lastDate: VenueTimeZone.dateTime(
        timeZone,
        year: now.year,
        month: now.month,
        day: now.day + 30,
      ),
      helpText: 'Choisissez la date',
      cancelText: 'Retour',
      confirmText: 'Continuer',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startsAt),
      helpText: 'Choisissez l’heure de début',
      cancelText: 'Retour',
      confirmText: 'Choisir',
    );
    if (time == null) return;
    setState(
      () => _startsAt = VenueTimeZone.dateTime(
        timeZone,
        year: date.year,
        month: date.month,
        day: date.day,
        hour: time.hour,
        minute: time.minute,
      ),
    );
  }

  Future<void> _reserve() async {
    final postId = _postId;
    if (postId == null || _working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final snapshot = _snapshot;
      if (snapshot?.canManage == true) {
        final customerId = _customerId;
        if (customerId == null) {
          setState(() => _error = 'Choisissez un client avant de réserver.');
          return;
        }
        await _repository.reserveForCustomer(
          postId: postId,
          customerId: customerId,
          startsAt: _startsAt,
          durationMinutes: _duration,
          timeZone: snapshot!.venue.timeZone,
        );
      } else {
        await _repository.reserve(
          postId: postId,
          startsAt: _startsAt,
          durationMinutes: _duration,
          timeZone: snapshot?.venue.timeZone ?? 'Africa/Algiers',
        );
      }
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              snapshot?.canManage == true
                  ? 'Réservation enregistrée.'
                  : 'Votre réservation est confirmée.',
            ),
          ),
        );
      }
    } on PostgrestException catch (error) {
      if (mounted) {
        setState(() => _error = reservationErrorMessage(error.message));
      }
    } catch (error, stackTrace) {
      debugPrint('Création de la réservation impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() => _error = 'La réservation n’a pas pu être créée.');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _createWalkInCustomer() async {
    final snapshot = _snapshot;
    if (snapshot == null || !snapshot.canManage || _working) return;
    final values = await showDialog<_WalkInCustomerValue>(
      context: context,
      builder: (context) => const _WalkInCustomerDialog(),
    );
    if (values == null || !mounted) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final customer = await _repository.createWalkInCustomer(
        venueId: snapshot.venue.id,
        fullName: values.fullName,
        phone: values.phone,
      );
      if (!mounted) return;
      setState(() => _customerId = customer.id);
      await _load();
    } on PostgrestException catch (error) {
      if (mounted) {
        setState(() => _error = reservationErrorMessage(error.message));
      }
    } catch (error, stackTrace) {
      debugPrint('Création du client impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() => _error = 'Le client n’a pas pu être ajouté.');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _changeStatus(ReservationItem reservation, String status) async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await _repository.setStatus(reservation.id, status);
      await _load();
    } on PostgrestException catch (error) {
      if (mounted) {
        setState(() => _error = reservationErrorMessage(error.message));
      }
    } catch (error, stackTrace) {
      debugPrint('Mise à jour de la réservation impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() => _error = 'La réservation n’a pas été modifiée.');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _cancel(ReservationItem reservation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Annuler la réservation ?'),
        content: const Text('Ce créneau sera à nouveau disponible.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Garder'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Annuler'),
          ),
        ],
      ),
    );
    if (confirmed != true || _working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await _repository.cancel(reservation.id);
      await _load();
    } on PostgrestException catch (error) {
      if (mounted) {
        setState(() => _error = reservationErrorMessage(error.message));
      }
    } catch (error, stackTrace) {
      debugPrint('Annulation de la réservation impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() => _error = 'La réservation n’a pas pu être annulée.');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final requestedReservationId = GoRouterState.of(
      context,
    ).uri.queryParameters['reservationId'];
    final snapshot = _snapshot;
    final isStaff = snapshot?.isStaff ?? (CurrentRoleCache.role != 'customer' && CurrentRoleCache.role != null);
    final reservations = snapshot?.reservations ?? const [];
    final now = snapshot == null
        ? DateTime.now()
        : VenueTimeZone.now(snapshot.venue.timeZone);
    final visibleReservations = isStaff
        ? reservations
        : reservations.where((item) => item.startsAt?.isAfter(now) ?? false);
    if (!_reservationJumpScheduled &&
        requestedReservationId != null &&
        snapshot != null) {
      _reservationJumpScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final targetContext = _reservationTargetKey.currentContext;
        if (targetContext != null) {
          Scrollable.ensureVisible(
            targetContext,
            duration: const Duration(milliseconds: 350),
            alignment: 0.2,
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cette réservation n’est plus affichée.'),
            ),
          );
        }
      });
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 22, 18, 24),
                  children: [
                    AppPageHeader(onBack: () => context.pop()),
                    const SizedBox(height: 18),
                    AppScreenTitle(
                      title: isStaff ? 'Réservations' : 'Postes & Réservations',
                      subtitle: isStaff
                          ? 'Planning de ${snapshot?.venue.name ?? 'la salle'}'
                          : 'Parcourez les postes disponibles et réservez votre session.',
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      _Notice(message: _error!, isError: true),
                    ],
                    if (_loading && snapshot == null)
                      const SizedBox(
                        height: 220,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (snapshot != null &&
                        snapshot.canManage &&
                        isStaff) ...[
                      const SizedBox(height: 18),
                      _buildBookingForm(snapshot, forStaff: true),
                    ] else if (snapshot != null && !isStaff) ...[
                      const SizedBox(height: 18),
                      if (snapshot.customer == null)
                        _Notice(
                          message:
                              'Liez votre compte à une salle avec le QR d’un poste avant de réserver.',
                          actionLabel: 'Scanner un QR',
                          onAction: () => context.go('/customer/scan'),
                        )
                      else
                        _buildBookingForm(snapshot),
                    ],
                    if (snapshot != null) ...[
                      const SizedBox(height: 22),
                      Text(
                        isStaff
                            ? 'Planning des réservations'
                            : 'Mes réservations',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (visibleReservations.isEmpty)
                        _Notice(
                          message: isStaff
                              ? 'Aucune réservation enregistrée.'
                              : 'Vous n’avez pas encore de réservation à venir.',
                        )
                      else
                        for (final reservation in visibleReservations)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 9),
                            child: _ReservationCard(
                              key: reservation.id == requestedReservationId
                                  ? _reservationTargetKey
                                  : null,
                              reservation: reservation,
                              isStaff: isStaff,
                              canManage: snapshot.canManage,
                              working: _working,
                              onCancel: () => isStaff
                                  ? _changeStatus(reservation, 'cancelled')
                                  : _cancel(reservation),
                              onComplete: () =>
                                  _changeStatus(reservation, 'completed'),
                              onNoShow: () =>
                                  _changeStatus(reservation, 'no_show'),
                            ),
                          ),
                    ],
                  ],
                ),
              ),
            ),
            AppBottomNav(currentIndex: isStaff ? 0 : 2, isStaff: isStaff),
          ],
        ),
      ),
    );
  }

  Widget _buildBookingForm(
    ReservationSnapshot snapshot, {
    bool forStaff = false,
  }) => AppSurface(
    isSelected: true,
    borderRadius: 22,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          forStaff
              ? 'Créer une réservation pour un client'
              : 'Choisissez un poste',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        if (forStaff) ...[
          if (snapshot.customers.isEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ajoutez le client à la salle ou créez un client sans compte.',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                TextButton.icon(
                  onPressed: _working ? null : _createWalkInCustomer,
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Ajouter un client sans compte'),
                ),
              ],
            )
          else
            Column(
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _customerId,
                  decoration: const InputDecoration(labelText: 'Client'),
                  items: [
                    for (final customer in snapshot.customers)
                      DropdownMenuItem(
                        value: customer.id,
                        child: Text(
                          customer.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _working
                      ? null
                      : (value) => setState(() => _customerId = value),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _working ? null : _createWalkInCustomer,
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: const Text('Ajouter un client sans compte'),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 12),
        ],
        if (snapshot.posts.isEmpty)
          const Text(
            'Aucun poste réservable pour le moment.',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          )
        else if (forStaff)
          DropdownButtonFormField<String>(
            initialValue: _postId,
            decoration: const InputDecoration(labelText: 'Poste'),
            items: [
              for (final post in snapshot.posts)
                DropdownMenuItem(
                  value: post['id'] as String,
                  child: Text(
                    '${post['name']} · ${post['screen_info'] ?? post['device']}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _working
                ? null
                : (value) => setState(() => _postId = value),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Postes disponibles',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 90,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: snapshot.posts.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final post = snapshot.posts[index];
                    final postId = post['id'] as String;
                    final isSelected = _postId == postId;
                    return InkWell(
                      onTap: _working ? null : () => setState(() => _postId = postId),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: 140,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0x26FF2A85) : const Color(0xFF16162D),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected ? AppColors.pink : const Color(0xFF26264F),
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.sports_esports_rounded,
                                  size: 18,
                                  color: isSelected ? AppColors.pink : const Color(0xFF8C8CA8),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    post['name'] as String? ?? 'Poste',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: isSelected ? Colors.white : const Color(0xFFD0D0E0),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              post['screen_info'] as String? ?? post['device'] as String? ?? 'Gaming',
                              style: const TextStyle(fontSize: 11, color: AppColors.muted),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: _working ? null : _chooseDate,
          icon: const Icon(Icons.calendar_month_rounded),
          label: Text(_formatDateTime(_startsAt)),
        ),
        const SizedBox(height: 12),
        const Text(
          'Durée',
          style: TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 7,
          children: [
            for (final minutes in [30, 60, 90, 120, 180, 240])
              ChoiceChip(
                label: Text('$minutes min'),
                selected: _duration == minutes,
                onSelected: _working
                    ? null
                    : (_) => setState(() => _duration = minutes),
              ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'La réservation est confirmée après vérification instantanée du créneau.',
          style: TextStyle(fontSize: 11, color: AppColors.muted),
        ),
        const SizedBox(height: 14),
        AppButton(
          label: _working
              ? 'Confirmation…'
              : forStaff
              ? 'Créer la réservation'
              : 'Confirmer la réservation',
          onPressed:
              _working ||
                  snapshot.posts.isEmpty ||
                  (forStaff && snapshot.customers.isEmpty)
              ? () {}
              : () {
                  _reserve();
                },
        ),
      ],
    ),
  );
}

class _WalkInCustomerValue {
  const _WalkInCustomerValue({required this.fullName, this.phone});

  final String fullName;
  final String? phone;
}

class _WalkInCustomerDialog extends StatefulWidget {
  const _WalkInCustomerDialog();

  @override
  State<_WalkInCustomerDialog> createState() => _WalkInCustomerDialogState();
}

class _WalkInCustomerDialogState extends State<_WalkInCustomerDialog> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Ajouter un client'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _nameController,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Nom du client'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Téléphone (facultatif)',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _error!,
              style: const TextStyle(color: AppColors.red, fontSize: 12),
            ),
          ),
        ],
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(
        onPressed: () {
          final fullName = _nameController.text.trim();
          if (fullName.length < 2) {
            setState(() => _error = 'Saisissez le nom du client.');
            return;
          }
          Navigator.pop(
            context,
            _WalkInCustomerValue(
              fullName: fullName,
              phone: _phoneController.text.trim(),
            ),
          );
        },
        child: const Text('Ajouter'),
      ),
    ],
  );
}

class _ReservationCard extends StatelessWidget {
  const _ReservationCard({
    super.key,
    required this.reservation,
    required this.isStaff,
    required this.canManage,
    required this.working,
    required this.onCancel,
    required this.onComplete,
    required this.onNoShow,
  });

  final ReservationItem reservation;
  final bool isStaff;
  final bool canManage;
  final bool working;
  final VoidCallback onCancel;
  final VoidCallback onComplete;
  final VoidCallback onNoShow;

  @override
  Widget build(BuildContext context) {
    final start = reservation.startsAt;
    final end = reservation.endsAt;
    final date = start == null
        ? 'Date inconnue'
        : '${DateFormat('dd MMMM yyyy · HH:mm', 'fr_FR').format(start)}'
              '${end == null ? '' : ' – ${DateFormat('HH:mm', 'fr_FR').format(end)}'}';
    final isConfirmed = reservation.status == 'confirmed';
    return AppSurface(
      borderRadius: 18,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.sports_esports_rounded,
                color: AppColors.primaryLight,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reservation.postName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (isStaff)
                      Text(
                        reservation.customerName,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.muted,
                        ),
                      ),
                  ],
                ),
              ),
              _StatusBadge(status: reservation.status),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            date,
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          if (isConfirmed && (!isStaff || canManage)) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                if (!isStaff)
                  TextButton.icon(
                    onPressed: working ? null : onCancel,
                    icon: const Icon(Icons.cancel_outlined, size: 16),
                    label: const Text('Annuler'),
                  ),
                if (isStaff && canManage) ...[
                  TextButton(
                    onPressed: working ? null : onCancel,
                    child: const Text('Annuler'),
                  ),
                  TextButton(
                    onPressed: working ? null : onComplete,
                    child: const Text('Terminée'),
                  ),
                  TextButton(
                    onPressed: working ? null : onNoShow,
                    child: const Text('Absent'),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final active = status == 'confirmed';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: (active ? AppColors.green : AppColors.muted).withValues(
          alpha: 0.15,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        reservationStatusLabel(status),
        style: TextStyle(
          fontSize: 10,
          color: active ? AppColors.green : AppColors.muted,
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.message,
    this.isError = false,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final bool isError;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => AppSurface(
    borderRadius: 16,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message,
          style: TextStyle(
            fontSize: 12,
            height: 1.4,
            color: isError ? AppColors.red : AppColors.muted,
          ),
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 10),
          TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ],
    ),
  );
}

String _formatDateTime(DateTime value) =>
    DateFormat('dd MMMM yyyy · HH:mm', 'fr_FR').format(value);
