import 'package:diu_ride/features/rides/data/models/passenger_request_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/core/utils/date_time_utils.dart';
import 'package:diu_ride/core/utils/same_account_guard.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';
import 'package:diu_ride/features/booking/presentation/widgets/booking_confirmation_sheet.dart';
import 'package:diu_ride/features/chat/presentation/screens/chat_screen.dart';
import 'package:diu_ride/features/rides/data/models/ride_model.dart';
import 'package:diu_ride/features/rides/data/models/vehicle_model.dart';
import 'package:diu_ride/features/rides/presentation/providers/rides_provider.dart';
import 'package:diu_ride/features/rides/presentation/widgets/post_ride_request_sheet.dart';
import 'package:diu_ride/features/rides/presentation/widgets/ride_result_card.dart';
import 'package:diu_ride/features/rides/presentation/widgets/my_rides_activity_view.dart';
import 'package:diu_ride/features/rides/presentation/screens/offer_ride_screen.dart';
import 'package:diu_ride/features/profile/presentation/widgets/motorcycle_config_dialog.dart';
import 'package:diu_ride/features/tracking/presentation/screens/ride_details_tracking_screen.dart';
import 'package:diu_ride/core/utils/direct_call_service.dart';
import 'package:diu_ride/core/providers/app_mode_provider.dart';

class AllSharedRidesScreen extends ConsumerStatefulWidget {
  const AllSharedRidesScreen({super.key});

  @override
  ConsumerState<AllSharedRidesScreen> createState() => _AllSharedRidesScreenState();
}

class _AllSharedRidesScreenState extends ConsumerState<AllSharedRidesScreen> {
  int _selectedMode = 0; // 0 = Available Bikes, 1 = Student Requests
  String _selectedLocation = 'All';
  bool _sortByLowestPrice = false;
  final TextEditingController _searchController = TextEditingController();

  final List<String> _locationFilters = [
    'All',
    'Uttara',
    'Mirpur',
    'Motijheel',
    'Dhanmondi',
    'Farmgate',
    'ECB Chattar',
    'Ashulia',
    'Birulia',
    'Savar',
    'Mohakhali',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appMode = ref.read(appModeProvider);
      if (appMode.isRider && mounted) {
        setState(() => _selectedMode = 1);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _handleBooking(RideModel ride) {
    BookingConfirmationSheet.show(
      context: context,
      ride: ride,
      onBookingSuccess: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF1C1C1E),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            content: Row(
              children: [
                const Icon(Icons.two_wheeler, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Moto Seat Requested from ${ride.driverName}! ৳${ride.farePerSeat.toInt()}',
                    style: AppTypography.labelMd.copyWith(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final allRidesAsync = ref.watch(allAvailableRidesProvider);
    final appMode = ref.watch(appModeProvider);

    // In Rider mode: only Ride Sharing Status (1) & Student Requests (2)
    // In Passenger mode: only Find Rides (0) & My Bookings (1)
    // In All mode: Find Rides (0), My Rides & Status (1), Requests (2)
    final effectiveMode = appMode.isRider
        ? (_selectedMode == 2 ? 2 : 1)
        : _selectedMode;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: Column(
          children: [
            // 1. Top Apple-style Search & Location Filter Header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            appMode.isRider
                                ? 'Biker Hub & Ride Status'
                                : (appMode.isPassenger ? 'Find DIU Peer Bikes' : 'All Shared Moto Rides'),
                            style: AppTypography.headlineSm.copyWith(
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF1C1C1E),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            appMode.isRider
                                ? 'Check ride sharing status & manage passenger bookings'
                                : 'Verified peer bikes commuting across Dhaka',
                            style: AppTypography.labelSm.copyWith(
                              color: const Color(0xFF8E8E93),
                            ),
                          ),
                        ],
                      ),
                      // Mode Pill
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: appMode.isRider ? const Color(0xFFFFF3E0) : const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.two_wheeler, size: 14, color: appMode.isRider ? const Color(0xFFE65100) : const Color(0xFF2E7D32)),
                            const SizedBox(width: 4),
                            Text(
                              appMode.isRider ? 'Biker Mode' : 'Bikes Only',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: appMode.isRider ? const Color(0xFFE65100) : const Color(0xFF2E7D32),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Sub-tab switcher: Mode-aware (Rider has ONLY Ride Sharing Status & Student Requests)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5E5EA),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        if (appMode.isRider) ...[
                          // 1. Ride Sharing Status (Biker posted rides & passengers)
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _selectedMode = 1),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: effectiveMode == 1 ? Colors.white : Colors.transparent,
                                  borderRadius: BorderRadius.circular(11),
                                  boxShadow: effectiveMode == 1
                                      ? [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.06),
                                            blurRadius: 4,
                                            offset: const Offset(0, 1),
                                          ),
                                        ]
                                      : null,
                                ),
                                alignment: Alignment.center,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.assignment_outlined,
                                      size: 15,
                                      color: effectiveMode == 1
                                          ? const Color(0xFFE65100)
                                          : const Color(0xFF8E8E93),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Ride Sharing Status',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: effectiveMode == 1 ? FontWeight.bold : FontWeight.w600,
                                        color: effectiveMode == 1
                                            ? const Color(0xFF141416)
                                            : const Color(0xFF8E8E93),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // 2. Student Pickup Requests
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _selectedMode = 2),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: effectiveMode == 2 ? Colors.white : Colors.transparent,
                                  borderRadius: BorderRadius.circular(11),
                                  boxShadow: effectiveMode == 2
                                      ? [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.06),
                                            blurRadius: 4,
                                            offset: const Offset(0, 1),
                                          ),
                                        ]
                                      : null,
                                ),
                                alignment: Alignment.center,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.hail,
                                      size: 15,
                                      color: effectiveMode == 2
                                          ? const Color(0xFFE65100)
                                          : const Color(0xFF8E8E93),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Student Requests',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: effectiveMode == 2 ? FontWeight.bold : FontWeight.w600,
                                        color: effectiveMode == 2
                                            ? const Color(0xFF141416)
                                            : const Color(0xFF8E8E93),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ] else ...[
                          // Passenger Mode: 2 clean tabs (Find Bikes & My Status)
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _selectedMode = 0),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: effectiveMode == 0 ? Colors.white : Colors.transparent,
                                  borderRadius: BorderRadius.circular(11),
                                  boxShadow: effectiveMode == 0
                                      ? [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.06),
                                            blurRadius: 4,
                                            offset: const Offset(0, 1),
                                          ),
                                        ]
                                      : null,
                                ),
                                alignment: Alignment.center,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.two_wheeler,
                                      size: 16,
                                      color: effectiveMode == 0
                                          ? const Color(0xFFE65100)
                                          : const Color(0xFF8E8E93),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Find Bikes',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: effectiveMode == 0 ? FontWeight.bold : FontWeight.w600,
                                        color: effectiveMode == 0
                                            ? const Color(0xFF141416)
                                            : const Color(0xFF8E8E93),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _selectedMode = 1),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: effectiveMode == 1 ? Colors.white : Colors.transparent,
                                  borderRadius: BorderRadius.circular(11),
                                  boxShadow: effectiveMode == 1
                                      ? [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.06),
                                            blurRadius: 4,
                                            offset: const Offset(0, 1),
                                          ),
                                        ]
                                      : null,
                                ),
                                alignment: Alignment.center,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.assignment_outlined,
                                      size: 16,
                                      color: effectiveMode == 1
                                          ? const Color(0xFFE65100)
                                          : const Color(0xFF8E8E93),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'My Status',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: effectiveMode == 1 ? FontWeight.bold : FontWeight.w600,
                                        color: effectiveMode == 1
                                            ? const Color(0xFF141416)
                                            : const Color(0xFF8E8E93),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  if (effectiveMode != 1) ...[

                  // Search input
                  Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2F2F7),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Filter by route, destination or driver...',
                        hintStyle: AppTypography.bodyMd.copyWith(color: const Color(0xFF8E8E93)),
                        prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF8E8E93)),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {});
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Location Filter Chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: [
                        ..._locationFilters.map((loc) {
                          final isSelected = _selectedLocation == loc;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedLocation = loc;
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                decoration: BoxDecoration(
                                  color: isSelected ? const Color(0xFFE65100) : Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isSelected
                                        ? const Color(0xFFE65100)
                                        : Colors.black.withOpacity(0.08),
                                  ),
                                  boxShadow: isSelected
                                      ? [
                                          BoxShadow(
                                            color: const Color(0xFFE65100).withOpacity(0.25),
                                            blurRadius: 6,
                                            offset: const Offset(0, 2),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Text(
                                  loc,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                    color: isSelected ? Colors.white : const Color(0xFF3A3A3C),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),

                        // Price Sort Toggle Pill
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _sortByLowestPrice = !_sortByLowestPrice;
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: _sortByLowestPrice
                                  ? const Color(0xFF34C759)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _sortByLowestPrice
                                    ? const Color(0xFF34C759)
                                    : Colors.black.withOpacity(0.08),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.swap_vert,
                                  size: 14,
                                  color: _sortByLowestPrice ? Colors.white : const Color(0xFF3A3A3C),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Price: Lowest',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: _sortByLowestPrice ? FontWeight.w700 : FontWeight.w600,
                                    color: _sortByLowestPrice ? Colors.white : const Color(0xFF3A3A3C),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                ],
              ),
            ),

            // 2. Rides List or My Rides & Status or Student Requests
            Expanded(
              child: effectiveMode == 1
                  ? MyRidesActivityView(
                      onOfferRide: () async {
                        if (appMode.isPassenger) return;
                        final nav = Navigator.of(context);
                        final ok = await MotorcycleConfigDialog.ensureConfigured(context, ref);
                        if (!ok || !mounted) return;
                        nav.push(
                          MaterialPageRoute(
                            builder: (_) => OfferRideScreen(
                              onRidePublished: () {
                                ref.invalidate(myPostedRidesProvider);
                                ref.invalidate(allAvailableRidesProvider);
                              },
                            ),
                          ),
                        );
                      },
                    )
                  : effectiveMode == 2
                      ? _buildStudentRequestsView()
                      : allRidesAsync.when(
                      data: (rides) {
                        // Filter strictly to bikes and exclude driver's own offered ride
                        final currentUser = ref.watch(authNotifierProvider).user;
                        var filtered = rides.where((r) => r.vehicle.type == VehicleType.bike && !isCurrentUserRide(r, currentUser)).toList();

                        // Filter by location
                        if (_selectedLocation != 'All') {
                          final query = _selectedLocation.toLowerCase();
                          filtered = filtered.where((r) {
                            return r.destinationName.toLowerCase().contains(query) ||
                                (r.destinationSubtitle?.toLowerCase().contains(query) ?? false) ||
                                r.originName.toLowerCase().contains(query) ||
                                r.routeCorridor.toLowerCase().contains(query);
                          }).toList();
                        }

                        // Filter by search text
                        final search = _searchController.text.trim().toLowerCase();
                        if (search.isNotEmpty) {
                          filtered = filtered.where((r) {
                            return r.destinationName.toLowerCase().contains(search) ||
                                r.originName.toLowerCase().contains(search) ||
                                r.driverName.toLowerCase().contains(search) ||
                                r.vehicle.modelName.toLowerCase().contains(search);
                          }).toList();
                        }

                        // Sort by price
                        if (_sortByLowestPrice) {
                          filtered.sort((a, b) => a.farePerSeat.compareTo(b.farePerSeat));
                        }

                        if (filtered.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF3E0),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Icon(Icons.two_wheeler, size: 32, color: Color(0xFFE65100)),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  'No Moto Rides Found',
                                  style: AppTypography.headlineSm.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'No peer rides matching "$_selectedLocation". Try clearing filters.',
                                  style: AppTypography.labelSm.copyWith(color: const Color(0xFF8E8E93)),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      _selectedLocation = 'All';
                                      _searchController.clear();
                                      _sortByLowestPrice = false;
                                    });
                                  },
                                  icon: const Icon(Icons.refresh, size: 16),
                                  label: const Text('Reset All Filters'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF141416),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        return RefreshIndicator(
                          color: const Color(0xFFE65100),
                          onRefresh: () async {
                            ref.invalidate(allAvailableRidesProvider);
                          },
                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final ride = filtered[index];
                              return RideResultCard(
                                ride: ride,
                                onBook: () => _handleBooking(ride),
                                onTapDetails: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => RideDetailsTrackingScreen(rideId: ride.id),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        );
                      },
                      loading: () => const Center(
                        child: CircularProgressIndicator(color: Color(0xFFE65100)),
                      ),
                      error: (err, _) => Center(
                        child: Text('Error: $err', style: AppTypography.bodyMd),
                      ),
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: appMode.isPassenger
          ? FloatingActionButton.extended(
              onPressed: () {
                PostRideRequestSheet.show(context);
              },
              backgroundColor: const Color(0xFF141416),
              icon: const Icon(Icons.hail, color: Color(0xFFFFA000), size: 20),
              label: const Text(
                'Request a Ride',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            )
          : FloatingActionButton.extended(
              onPressed: () async {
                final nav = Navigator.of(context);
                final ok = await MotorcycleConfigDialog.ensureConfigured(context, ref);
                if (!ok || !mounted) return;
                nav.push(
                  MaterialPageRoute(
                    builder: (_) => OfferRideScreen(
                      onRidePublished: () {
                        ref.invalidate(myPostedRidesProvider);
                        ref.invalidate(allAvailableRidesProvider);
                      },
                    ),
                  ),
                );
              },
              backgroundColor: const Color(0xFF0F172A),
              icon: const Icon(Icons.add, color: Colors.white, size: 20),
              label: const Text(
                'Post a Moto Ride',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
    );
  }

  Widget _buildStudentRequestsView() {
    final ridesRepo = ref.watch(ridesRepositoryProvider);
    final user = ref.watch(authNotifierProvider).user;
    final appMode = ref.watch(appModeProvider);

    final requestsAsync = ref.watch(allPassengerRequestsProvider);

    return requestsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFE65100))),
      error: (e, _) => Center(
        child: Text('Failed to load requests: $e', style: const TextStyle(color: Colors.grey)),
      ),
      data: (rawRequests) {
        final myRequests = rawRequests.where((req) => isCurrentUserPassengerRequest(req, user)).toList();
        var otherRequests = rawRequests.where((req) => !isCurrentUserPassengerRequest(req, user)).toList();

        // 1. Filter by location
        if (_selectedLocation != 'All') {
          final query = _selectedLocation.toLowerCase();
          otherRequests = otherRequests.where((req) {
            final isMap = req is Map<String, dynamic>;
            final pickup = (isMap ? (req['pickup'] ?? '') : (req.pickup ?? '')).toString().toLowerCase();
            final dropoff = (isMap ? (req['dropoff'] ?? '') : (req.dropoff ?? '')).toString().toLowerCase();
            return pickup.contains(query) || dropoff.contains(query);
          }).toList();
        }

        // 2. Filter by search keywords
        final search = _searchController.text.trim().toLowerCase();
        if (search.isNotEmpty) {
          otherRequests = otherRequests.where((req) {
            final isMap = req is Map<String, dynamic>;
            final pName = (isMap ? (req['passengerName'] ?? '') : (req.passengerName ?? '')).toString().toLowerCase();
            final pDept = (isMap ? (req['passengerDept'] ?? '') : (req.passengerDept ?? '')).toString().toLowerCase();
            final pickup = (isMap ? (req['pickup'] ?? '') : (req.pickup ?? '')).toString().toLowerCase();
            final dropoff = (isMap ? (req['dropoff'] ?? '') : (req.dropoff ?? '')).toString().toLowerCase();
            final notes = (isMap ? (req['notes'] ?? '') : (req.notes ?? '')).toString().toLowerCase();
            return pName.contains(search) || pDept.contains(search) || pickup.contains(search) || dropoff.contains(search) || notes.contains(search);
          }).toList();
        }

        // 3. Sort by lowest price
        if (_sortByLowestPrice) {
          otherRequests.sort((a, b) {
            final fareA = (a is Map ? (a['proposedFare'] ?? 0.0) : (a.proposedFare ?? 0.0)) as num;
            final fareB = (b is Map ? (b['proposedFare'] ?? 0.0) : (b.proposedFare ?? 0.0)) as num;
            return fareA.compareTo(fareB);
          });
        }

        final requests = [...myRequests, ...otherRequests];

        if (requests.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.hail, size: 32, color: Color(0xFFE65100)),
                ),
                const SizedBox(height: 14),
                Text(
                  'No Student Requests Yet',
                  style: AppTypography.headlineSm.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  'Students who request a ride will appear here.\nAny biker can accept their request to ride together.',
                  textAlign: TextAlign.center,
                  style: AppTypography.labelSm.copyWith(color: const Color(0xFF8E8E93)),
                ),
                const SizedBox(height: 16),
                if (!appMode.isRider)
                  ElevatedButton.icon(
                    onPressed: () => PostRideRequestSheet.show(context),
                    icon: const Icon(Icons.send_rounded, size: 16),
                    label: const Text('Post a Ride Request Now'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF141416),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: () async {
                      final ok = await MotorcycleConfigDialog.ensureConfigured(context, ref);
                      if (!ok || !mounted) return;
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => OfferRideScreen(
                            onRidePublished: () {
                              ref.invalidate(myPostedRidesProvider);
                              ref.invalidate(allAvailableRidesProvider);
                            },
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.two_wheeler, size: 16),
                    label: const Text('Offer a Ride to Students'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE65100),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          color: const Color(0xFFE65100),
          onRefresh: () async {
            ref.invalidate(allPassengerRequestsProvider);
            ref.invalidate(myPassengerRequestsProvider);
            ref.invalidate(passengerRequestsProvider);
          },
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
            itemCount: requests.length,
            itemBuilder: (context, index) {
              final req = requests[index];
              final isMap = req is Map<String, dynamic>;
              final id = isMap ? (req['id'] ?? '') : (req.id ?? '');
              final pId = isMap ? (req['passengerId'] ?? '') : (req.passengerId ?? '');
              final pName = isMap ? (req['passengerName'] ?? 'Student') : (req.passengerName ?? 'Student');
              final pDept = isMap ? (req['passengerDept'] ?? 'CSE') : (req.passengerDept ?? 'CSE');
              final pPhone = isMap ? (req['passengerPhone'] ?? '') : (req.passengerPhone ?? '');
              final pickup = isMap ? (req['pickup'] ?? '') : (req.pickup ?? '');
              final dropoff = isMap ? (req['dropoff'] ?? '') : (req.dropoff ?? '');
              final time = isMap ? (req['requestedTime'] ?? '') : (req.requestedTime ?? '');
              final fare = isMap ? (req['proposedFare'] ?? 50.0) : (req.proposedFare ?? 50.0);
              final status = isMap ? (req['status'] ?? 'open') : (req.status ?? 'open');
              final isAccepted = status == 'accepted';
              final isMyRequest = isCurrentUserPassengerRequest(req, user);

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isAccepted ? const Color(0xFF34C759).withOpacity(0.4) : Colors.black.withOpacity(0.06),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: const Color(0xFFFFF3E0),
                          child: Text(
                            pName.isNotEmpty ? pName[0].toUpperCase() : 'S',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFE65100)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(pName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                  if (isMyRequest) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE3F2FD),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text('You', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF1976D2))),
                                    ),
                                  ],
                                ],
                              ),
                              Builder(
                                builder: (_) {
                                  final createdAtRaw = isMap ? (req['createdAt'] ?? req['created_at']) : (req.createdAt);
                                  final createdDt = createdAtRaw != null ? DateTime.tryParse(createdAtRaw.toString()) : null;
                                  final postTimeStr = DateTimeUtils.formatPostingTime(createdDt);
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '$pDept • 🕒 Posted: $postTimeStr',
                                        style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93)),
                                      ),
                                      if (time.isNotEmpty)
                                        Text(
                                          '⏰ Scheduled: $time',
                                          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFFE65100)),
                                        ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isAccepted ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '৳${fare is num ? fare.toInt() : fare}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: isAccepted ? const Color(0xFF2E7D32) : const Color(0xFFE65100),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F9FA),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.trip_origin, size: 14, color: Color(0xFF2E7D32)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(pickup, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                          const Icon(Icons.arrow_forward, size: 12, color: Colors.grey),
                          const SizedBox(width: 6),
                          const Icon(Icons.location_on, size: 14, color: Color(0xFFFF3B30)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(dropoff, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        if (pPhone.isNotEmpty) ...[
                          IconButton(
                            onPressed: () {
                              DirectCallService.showCallOptions(
                                context,
                                phoneNumber: pPhone,
                                peerName: pName,
                              );
                            },
                            icon: const Icon(Icons.call, size: 16, color: Color(0xFF2E7D32)),
                            tooltip: 'Direct Call $pName',
                            style: IconButton.styleFrom(
                              backgroundColor: const Color(0xFFE8F5E9),
                              padding: const EdgeInsets.all(8),
                              minimumSize: Size.zero,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (isMyRequest) ...[
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ChatScreen(
                                      rideId: id,
                                      peerName: isAccepted ? 'Biker' : 'Campus Commute',
                                      vehicleModel: 'My Ride Request',
                                      peerPhone: pPhone,
                                      peerRole: 'Driver',
                                      peerId: isMap ? (req['acceptedDriverId'] ?? req['driver_id'])?.toString() : null,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.chat_bubble_outline, size: 15),
                              label: Text(isAccepted ? 'Chat with Rider' : 'View Chat'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF1976D2),
                                side: const BorderSide(color: Color(0xFF1976D2)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          OutlinedButton.icon(
                            onPressed: () {
                              final reqModel = req is PassengerRequestModel
                                  ? req
                                  : PassengerRequestModel.fromJson(Map<String, dynamic>.from(req as Map));
                              PostRideRequestSheet.show(context, existingRequest: reqModel);
                            },
                            icon: const Icon(Icons.edit_outlined, size: 15),
                            label: const Text('Edit'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFE65100),
                              side: const BorderSide(color: Color(0xFFFFCC80)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                          const SizedBox(width: 6),
                          ElevatedButton.icon(
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  title: const Text('Cancel Your Request?'),
                                  content: Text('Are you sure you want to remove your ride request to $dropoff?'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: const Text('Keep'),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFFE53935),
                                        foregroundColor: Colors.white,
                                      ),
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Cancel & Remove'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                final ok = await ridesRepo.deletePassengerRequest(id);
                                if (context.mounted) {
                                  ref.invalidate(allPassengerRequestsProvider);
                                  ref.invalidate(passengerRequestsProvider);
                                  ref.invalidate(myPassengerRequestsProvider);
                                  setState(() {});
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      backgroundColor: const Color(0xFFE53935),
                                      content: Text(ok ? 'Your ride request has been cancelled and removed.' : 'Request removed.'),
                                    ),
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.delete_forever, size: 15),
                            label: const Text('Delete'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFE53935),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ] else if (isAccepted) ...[
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ChatScreen(
                                      rideId: id,
                                      peerName: pName,
                                      vehicleModel: 'Student Ride Request',
                                      peerPhone: pPhone,
                                      peerRole: 'Passenger',
                                      peerId: pId,
                                      chatContext: 'from_passenger_request',
                                      sourcePostId: id,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.chat, size: 15),
                              label: const Text('Chat with Passenger'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF34C759),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  title: const Text('Delete Request?'),
                                  content: Text('Remove this request for $pName ($pickup → $dropoff)?'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE53935), foregroundColor: Colors.white),
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                await ridesRepo.deletePassengerRequest(id);
                                if (context.mounted) {
                                  ref.invalidate(allPassengerRequestsProvider);
                                  ref.invalidate(passengerRequestsProvider);
                                  ref.invalidate(myPassengerRequestsProvider);
                                  setState(() {});
                                }
                              }
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.all(9),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFEBEE),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFFFCDD2)),
                              ),
                              child: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFE53935)),
                            ),
                          ),
                        ] else ...[
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                if (SameAccountGuard.blockOwnPassengerAccept(context, user, req)) {
                                  return;
                                }
                                final currentUserId = user?.id ?? 'drv_peer';
                                final currentUserName = user?.name ?? 'Campus Biker';
                                final currentUserPhone = user?.phone ?? '01712345678';

                                try {
                                  final ok = await ridesRepo.acceptPassengerRequest(
                                    requestId: id,
                                    driverId: currentUserId,
                                    driverName: currentUserName,
                                    driverPhone: currentUserPhone,
                                    driverBike: user?.vehicleInfo ?? 'Campus Motorcycle',
                                    driverStudentId: user?.studentId,
                                  );

                                  if (!context.mounted) return;
                                  ref.invalidate(allPassengerRequestsProvider);
                                  ref.invalidate(passengerRequestsProvider);
                                  ref.invalidate(myPassengerRequestsProvider);
                                  setState(() {});
                                  if (!ok) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        backgroundColor: Color(0xFFB45309),
                                        content: Text('Could not accept this request.'),
                                      ),
                                    );
                                    return;
                                  }
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      backgroundColor: const Color(0xFF1C1C1E),
                                      content: Text('Ride Request Accepted! You will commute with $pName.'),
                                    ),
                                  );
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => ChatScreen(
                                        rideId: id,
                                        peerName: pName,
                                        vehicleModel: 'Accepted Commute',
                                        peerPhone: pPhone,
                                        peerRole: 'Passenger',
                                        peerId: pId,
                                        chatContext: 'from_passenger_request',
                                        sourcePostId: id,
                                      ),
                                    ),
                                  );
                                } catch (e) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      backgroundColor: const Color(0xFFB45309),
                                      content: Text(e.toString().replaceFirst('Exception: ', '')),
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.check_circle_outline, size: 16),
                              label: const Text('Accept Request (রাইড গ্রহণ করুন)'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF141416),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  title: const Text('Delete Student Request?'),
                                  content: Text('Remove this request for $pName ($pickup → $dropoff)?'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE53935), foregroundColor: Colors.white),
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                await ridesRepo.deletePassengerRequest(id);
                                if (context.mounted) {
                                  ref.invalidate(passengerRequestsProvider);
                                  setState(() {});
                                }
                              }
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.all(9),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFEBEE),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFFFCDD2)),
                              ),
                              child: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFE53935)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
