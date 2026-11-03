import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:diu_ride/core/constants/app_colors.dart';
import 'package:diu_ride/core/constants/campus_locations.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/features/booking/presentation/widgets/booking_confirmation_sheet.dart';
import 'package:diu_ride/features/tracking/presentation/screens/ride_details_tracking_screen.dart';
import 'package:diu_ride/features/rides/data/models/ride_model.dart';
import 'package:diu_ride/features/rides/presentation/providers/rides_provider.dart';
import 'package:diu_ride/features/rides/presentation/widgets/ride_result_card.dart';
import 'package:diu_ride/features/rides/presentation/widgets/search_filter_chips.dart';
import 'package:diu_ride/features/rides/presentation/widgets/search_route_card.dart';
import 'package:diu_ride/core/services/location_search_service.dart';
import 'package:diu_ride/features/map/presentation/widgets/location_autocomplete_input.dart';
import 'package:diu_ride/features/map/presentation/screens/full_screen_commute_map_screen.dart';

class SearchRidesScreen extends ConsumerStatefulWidget {
  const SearchRidesScreen({super.key});

  @override
  ConsumerState<SearchRidesScreen> createState() => _SearchRidesScreenState();
}

class _SearchRidesScreenState extends ConsumerState<SearchRidesScreen> {
  final _searchController = TextEditingController();
  String _selectedQuickTag = 'All';
  bool _isMapView = false;
  GoogleMapController? _mapController;
  RideModel? _selectedMapRide;
  RouteSuggestion? _selectedRouteSuggestion;
  Set<Polyline> _mapPolylines = {};

  final List<String> _quickTags = [
    'All',
    'Uttara',
    'Mirpur',
    'Dhanmondi',
    'Gate 1',
    'Birulia',
    'Ashulia',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showBookingSheet(ride) {
    BookingConfirmationSheet.show(
      context: context,
      ride: ride,
      onBookingSuccess: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            content: Text(
              'Seat Reserved! Driver ${ride.driverName} notified.',
              style: AppTypography.bodyMdMedium.copyWith(color: Colors.white),
            ),
          ),
        );
      },
    );
  }

  void _onQuickTagSelected(String tag) {
    setState(() => _selectedQuickTag = tag);
    final notifier = ref.read(rideSearchFilterProvider.notifier);
    if (tag == 'All') {
      _searchController.clear();
      notifier.setGeneralSearch('');
    } else {
      _searchController.text = tag;
      notifier.setGeneralSearch(tag);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filterState = ref.watch(rideSearchFilterProvider);
    final filterNotifier = ref.read(rideSearchFilterProvider.notifier);
    final resultsAsync = ref.watch(searchRidesResultsProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Top Mode Switcher (All Rides vs Route Planner)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          if (!filterState.isAllRidesMode) {
                            filterNotifier.setAllRidesMode(true);
                          }
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: filterState.isAllRidesMode ? Colors.white : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: filterState.isAllRidesMode
                                ? [const BoxShadow(color: AppColors.cardShadow, blurRadius: 4, offset: Offset(0, 1))]
                                : null,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.two_wheeler,
                                size: 16,
                                color: filterState.isAllRidesMode ? AppColors.primary : AppColors.outline,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'All Moto Rides',
                                style: AppTypography.labelMd.copyWith(
                                  fontWeight: filterState.isAllRidesMode ? FontWeight.bold : FontWeight.w500,
                                  color: filterState.isAllRidesMode ? AppColors.primary : AppColors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          if (filterState.isAllRidesMode) {
                            filterNotifier.setAllRidesMode(false);
                            if (filterState.pickupQuery.isEmpty) {
                              filterNotifier.setPickup('DIU Smart City, Ashulia');
                              filterNotifier.setDropoff('Uttara Sector 11');
                            }
                          }
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: !filterState.isAllRidesMode ? Colors.white : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: !filterState.isAllRidesMode
                                ? [const BoxShadow(color: AppColors.cardShadow, blurRadius: 4, offset: Offset(0, 1))]
                                : null,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.route,
                                size: 16,
                                color: !filterState.isAllRidesMode ? AppColors.primary : AppColors.outline,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Bike Route',
                                style: AppTypography.labelMd.copyWith(
                                  fontWeight: !filterState.isAllRidesMode ? FontWeight.bold : FontWeight.w500,
                                  color: !filterState.isAllRidesMode ? AppColors.primary : AppColors.onSurfaceVariant,
                                ),
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

            // Mode 1: All Rides - Live Search Input with Google Places Autocomplete & Map Picker
            if (filterState.isAllRidesMode) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: LocationAutocompleteInput(
                  controller: _searchController,
                  hintText: 'Search destination (e.g. Motijheel, Mirpur 10)...',
                  prefixIcon: Icons.search,
                  prefixColor: AppColors.primary,
                  showMapPicker: true,
                  onChanged: (val) {
                    filterNotifier.setGeneralSearch(val);
                    if (val.isEmpty) {
                      setState(() => _selectedQuickTag = 'All');
                    }
                  },
                  onLocationSelected: (loc) {
                    _searchController.text = loc.title;
                    filterNotifier.setGeneralSearch(loc.title);
                    setState(() => _selectedQuickTag = loc.title);
                  },
                ),
              ),

              // Quick Location Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: _quickTags.map((tag) {
                    final isSel = _selectedQuickTag == tag;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(tag),
                        selected: isSel,
                        onSelected: (_) => _onQuickTagSelected(tag),
                        selectedColor: AppColors.primaryContainer,
                        checkmarkColor: AppColors.primary,
                        labelStyle: TextStyle(
                          fontSize: 12,
                          color: isSel ? AppColors.primary : AppColors.onSurfaceVariant,
                          fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                        ),
                        backgroundColor: AppColors.surfaceContainerLow,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: isSel ? AppColors.primary : Colors.transparent,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ] else ...[
              // Mode 2: Route Planner (Pickup & Dropoff Cards)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: SearchRouteCard(
                  pickup: filterState.pickupQuery,
                  dropoff: filterState.dropoffQuery,
                  seats: filterState.seatsNeeded,
                  departureTime: filterState.departureTime,
                  onPickupChanged: filterNotifier.setPickup,
                  onDropoffChanged: filterNotifier.setDropoff,
                  onSwap: filterNotifier.swapLocations,
                  onGpsTap: () {
                    filterNotifier.setPickup('DIU Smart City, Ashulia');
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Pickup set to current campus location.')),
                    );
                  },
                  onSeatsChanged: filterNotifier.setSeatsNeeded,
                  onSelectTime: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Departure scheduled for today.')),
                    );
                  },
                ),
              ),
            ],

            // Horizontal Filter Chips (Vehicles, Female only, Lowest price)
            SearchFilterChips(
              filterState: filterState,
              notifier: filterNotifier,
            ),
            const SizedBox(height: 4),

            // Results count status bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      resultsAsync.when(
                        data: (rides) => Text(
                          '${rides.length} Rides Available',
                          style: AppTypography.labelLg.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.onSurface,
                          ),
                        ),
                        loading: () => Text(
                          'Searching rides...',
                          style: AppTypography.labelLg,
                        ),
                        error: (_, __) => Text(
                          '0 Rides Available',
                          style: AppTypography.labelLg,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '• Ashulia Corridor',
                        style: AppTypography.labelSm.copyWith(color: AppColors.outline),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      if (filterState.generalSearchQuery.isNotEmpty || filterState.vehicleType != null || filterState.femaleOnly) ...[
                        InkWell(
                          onTap: () {
                            _searchController.clear();
                            filterNotifier.clearFilters();
                            setState(() => _selectedQuickTag = 'All');
                          },
                          child: Text(
                            'Clear',
                            style: AppTypography.labelSm.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      InkWell(
                        onTap: () => setState(() {
                          _isMapView = !_isMapView;
                          _selectedMapRide = null;
                        }),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _isMapView ? const Color(0xFFE65100) : const Color(0xFFFFF3E0),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFE65100)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _isMapView ? Icons.format_list_bulleted : Icons.map_outlined,
                                size: 14,
                                color: _isMapView ? Colors.white : const Color(0xFFE65100),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _isMapView ? 'List' : 'Live Map',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: _isMapView ? Colors.white : const Color(0xFFE65100),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Results feed
            Expanded(
              child: resultsAsync.when(
                data: (rides) {
                  if (_isMapView) {
                    return _buildMapRideExplorer(rides);
                  }
                  if (rides.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.commute, size: 52, color: AppColors.outlineVariant),
                            const SizedBox(height: 12),
                            Text(
                              'No matching rides found',
                              style: AppTypography.headlineSm.copyWith(color: AppColors.onSurface),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Try searching a different location or reset filters to see all available rides.',
                              style: AppTypography.bodyMd.copyWith(color: AppColors.outline),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: () {
                                _searchController.clear();
                                filterNotifier.clearFilters();
                                setState(() => _selectedQuickTag = 'All');
                              },
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('View All Campus Rides'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: () async {
                      ref.invalidate(searchRidesResultsProvider);
                      ref.invalidate(departingSoonRidesProvider);
                      ref.invalidate(allAvailableRidesProvider);
                    },
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                      itemCount: rides.length,
                      itemBuilder: (context, index) {
                        final ride = rides[index];
                        return RideResultCard(
                          ride: ride,
                          onBook: () => _showBookingSheet(ride),
                          onTapDetails: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => RideDetailsTrackingScreen(
                                  rideId: ride.id,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
                error: (err, _) => Center(
                  child: Text('Error loading rides: $err'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapRideExplorer(List<RideModel> rides) {
    final markers = <Marker>{};

    // DIU Campus Origin marker
    markers.add(
      Marker(
        markerId: const MarkerId('diu_campus_hub'),
        position: const LatLng(CampusLocations.diuCenterLat, CampusLocations.diuCenterLng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: '🏛️ DIU Smart City Hub', snippet: 'Ashulia Campus'),
      ),
    );

    for (final ride in rides) {
      markers.add(
        Marker(
          markerId: MarkerId('ride_${ride.id}'),
          position: LatLng(ride.destinationLat, ride.destinationLng),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            _selectedMapRide?.id == ride.id ? BitmapDescriptor.hueRed : BitmapDescriptor.hueOrange,
          ),
          infoWindow: InfoWindow(
            title: '🏍️ ${ride.driverName} (৳${ride.farePerSeat.toInt()})',
            snippet: '${ride.originName} ➔ ${ride.destinationName}',
          ),
          onTap: () async {
            setState(() {
              _selectedMapRide = ride;
              _selectedRouteSuggestion = null;
            });
            _mapController?.animateCamera(
              CameraUpdate.newLatLngZoom(LatLng(ride.destinationLat, ride.destinationLng), 13.0),
            );
            final origin = LatLng(ride.originLat, ride.originLng);
            final dest = LatLng(ride.destinationLat, ride.destinationLng);
            final route = await LocationSearchService.getRoute(origin, dest);
            if (mounted && _selectedMapRide?.id == ride.id) {
              setState(() {
                _selectedRouteSuggestion = route;
                _mapPolylines = {
                  Polyline(
                    polylineId: const PolylineId('selected_ride_casing'),
                    points: route.polylinePoints,
                    color: const Color(0xFF1565C0),
                    width: 6,
                  ),
                  Polyline(
                    polylineId: const PolylineId('selected_ride_route'),
                    points: route.polylinePoints,
                    color: const Color(0xFF42A5F5),
                    width: 4,
                  ),
                };
              });
            }
          },
        ),
      );
    }

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: const CameraPosition(
            target: LatLng(CampusLocations.diuCenterLat, CampusLocations.diuCenterLng),
            zoom: 12.0,
          ),
          onMapCreated: (ctrl) => _mapController = ctrl,
          markers: markers,
          polylines: _mapPolylines,
          myLocationEnabled: true,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          scrollGesturesEnabled: true,
          zoomGesturesEnabled: true,
          rotateGesturesEnabled: true,
          tiltGesturesEnabled: true,
          gestureRecognizers: {
            Factory<OneSequenceGestureRecognizer>(
              () => EagerGestureRecognizer(),
            ),
          },
          onTap: (_) {
            if (_selectedMapRide != null) {
              setState(() {
                _selectedMapRide = null;
                _selectedRouteSuggestion = null;
                _mapPolylines = {};
              });
            }
          },
        ),
        // Overlay banner with Full Screen Map access
        Positioned(
          top: 10,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.96),
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
            ),
            child: Row(
              children: [
                const Icon(Icons.two_wheeler, size: 18, color: Color(0xFFE65100)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _selectedRouteSuggestion != null
                        ? 'Road Path: ${_selectedRouteSuggestion!.distanceKm.toStringAsFixed(1)} km • ~${_selectedRouteSuggestion!.durationMinutes} mins'
                        : 'Tap any biker pin to see Google road route & reserve',
                    style: AppTypography.labelSm.copyWith(
                      color: const Color(0xFF1F2937),
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                InkWell(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => FullScreenCommuteMapScreen(
                          initialDestination: _selectedMapRide != null
                              ? LatLng(_selectedMapRide!.destinationLat, _selectedMapRide!.destinationLng)
                              : null,
                          initialDestinationName: _selectedMapRide?.destinationName,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE65100).withOpacity(0.4)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Full Map', style: TextStyle(color: Color(0xFFE65100), fontSize: 11, fontWeight: FontWeight.bold)),
                        SizedBox(width: 2),
                        Icon(Icons.fullscreen, size: 14, color: Color(0xFFE65100)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Floating selected ride card
        if (_selectedMapRide != null)
          Positioned(
            left: 14,
            right: 14,
            bottom: 16,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 14, offset: Offset(0, 4)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF3E0),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.two_wheeler, color: Color(0xFFE65100), size: 20),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selectedMapRide!.driverName,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                              ),
                              Text(
                                '${_selectedMapRide!.vehicle.modelName} • ${_selectedMapRide!.availableSeats} seats',
                                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE65100),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '৳${_selectedMapRide!.farePerSeat.toInt()}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${_selectedMapRide!.originName} ➔ ${_selectedMapRide!.destinationName}',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => RideDetailsTrackingScreen(
                                  rideId: _selectedMapRide!.id,
                                ),
                              ),
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF1F2937),
                            side: const BorderSide(color: Color(0xFFD1D5DB)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          child: const Text('View Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _showBookingSheet(_selectedMapRide!),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE65100),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          child: const Text('Reserve Seat', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
