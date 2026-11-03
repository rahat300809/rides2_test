import 'package:diu_ride/core/providers/app_mode_provider.dart';
import 'package:diu_ride/features/rides/data/models/passenger_request_model.dart';
import 'package:diu_ride/shared/widgets/visitor_mode_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';
import 'package:diu_ride/features/rides/presentation/providers/rides_provider.dart';
import 'package:diu_ride/features/map/presentation/widgets/location_autocomplete_input.dart';

class PostRideRequestSheet extends ConsumerStatefulWidget {
  final PassengerRequestModel? existingRequest;

  const PostRideRequestSheet({
    super.key,
    this.existingRequest,
  });

  static Future<void> show(BuildContext context, {PassengerRequestModel? existingRequest}) {
    if (existingRequest == null) {
      try {
        final container = ProviderScope.containerOf(context, listen: false);
        final appMode = container.read(appModeProvider);
        if (appMode.isRider) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Color(0xFF1E293B),
              behavior: SnackBarBehavior.floating,
              content: Text('Biker Mode is active. Switch to Passenger mode to post a ride request, or tap Offer Ride.'),
            ),
          );
          return Future.value();
        }
      } catch (_) {}
    }
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PostRideRequestSheet(existingRequest: existingRequest),
    );
  }

  @override
  ConsumerState<PostRideRequestSheet> createState() => _PostRideRequestSheetState();
}

class _PostRideRequestSheetState extends ConsumerState<PostRideRequestSheet> {
  final _pickupController = TextEditingController(text: 'DIU Smart City, Ashulia');
  final _dropoffController = TextEditingController();
  final _notesController = TextEditingController();
  final _timeController = TextEditingController(text: 'Right Now (Next 15m)');
  final _fareController = TextEditingController(text: '50');
  double _proposedFare = 50.0;
  String _selectedTime = 'Right Now (Next 15m)';
  bool _isLoading = false;

  final List<String> _quickDestinations = [
    'Uttara Sector 11',
    'Uttara House Building',
    'Mirpur 10 Circle',
    'Dhanmondi 27',
    'Birulia Bridge',
    'Ashulia Bus Stand',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.existingRequest == null && ref.read(appModeProvider).isRider) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF1E293B),
            behavior: SnackBarBehavior.floating,
            content: Text('Biker Mode is active. Switch to Passenger mode to post a ride request.'),
          ),
        );
      }
    });
    if (widget.existingRequest != null) {
      final req = widget.existingRequest!;
      _pickupController.text = req.pickup;
      _dropoffController.text = req.dropoff;
      _notesController.text = req.notes;
      _timeController.text = req.requestedTime;
      _selectedTime = req.requestedTime;
      _proposedFare = req.proposedFare;
      _fareController.text = req.proposedFare.toInt().toString();
    }
  }

  final List<String> _quickTimes = [
    'Right Now (Next 15m)',
    'Post-Class (2:30 PM)',
    'Evening (5:00 PM)',
    'Tomorrow Morning',
  ];

  Future<void> _pickCustomTimeAndDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (pickedTime == null || !mounted) return;

    final hour = pickedTime.hourOfPeriod == 0 ? 12 : pickedTime.hourOfPeriod;
    final minute = pickedTime.minute.toString().padLeft(2, '0');
    final period = pickedTime.period == DayPeriod.am ? 'AM' : 'PM';
    final dateStr = '${pickedDate.day}/${pickedDate.month}';
    final formatted = '$dateStr at $hour:$minute $period';

    setState(() {
      _selectedTime = formatted;
      _timeController.text = formatted;
    });
  }

  @override
  void dispose() {
    _pickupController.dispose();
    _dropoffController.dispose();
    _notesController.dispose();
    _timeController.dispose();
    _fareController.dispose();
    super.dispose();
  }

  Future<void> _submitRequest() async {
    if (checkAndEnforceVisitorMode(context, ref, actionName: 'broadcast a ride request')) return;
    final pickup = _pickupController.text.trim();
    final dropoff = _dropoffController.text.trim();
    if (pickup.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a pickup location!')),
      );
      return;
    }
    if (dropoff.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter or select a destination!')),
      );
      return;
    }
    if (pickup.toLowerCase() == dropoff.toLowerCase()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pickup and destination cannot be the same!')),
      );
      return;
    }

    final customFare = double.tryParse(_fareController.text.trim()) ?? _proposedFare;
    if (customFare <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Proposed fare must be greater than zero!')),
      );
      return;
    }

    final customTime = _timeController.text.trim().isNotEmpty
        ? _timeController.text.trim()
        : _selectedTime;

    setState(() => _isLoading = true);

    try {
      final user = ref.read(authNotifierProvider).user;
      final ridesRepo = ref.read(ridesRepositoryProvider);

      if (widget.existingRequest != null) {
        await ridesRepo.updatePassengerRequest(
          requestId: widget.existingRequest!.id,
          pickup: _pickupController.text.trim(),
          dropoff: dropoff,
          requestedTime: customTime,
          proposedFare: customFare,
          notes: _notesController.text.trim(),
        );
      } else {
        await ridesRepo.createPassengerRequest(
          passengerId: user?.id ?? 'usr_student',
          passengerName: user?.name ?? 'DIU Student',
          passengerPhone: user?.phone ?? '01712345678',
          pickup: _pickupController.text.trim(),
          dropoff: dropoff,
          requestedTime: customTime,
          proposedFare: customFare,
          notes: _notesController.text.trim(),
        );
      }

      ref.invalidate(allPassengerRequestsProvider);
      ref.invalidate(myPassengerRequestsProvider);
      ref.invalidate(passengerRequestsProvider);

      if (!mounted) return;
      Navigator.of(context).pop();

      final isEditing = widget.existingRequest != null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF1C1C1E),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Color(0xFF34C759), size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isEditing
                      ? 'Ride Request Updated! Pickup: ${_pickupController.text.trim()} ➔ $dropoff (৳${customFare.toInt()}).'
                      : 'Ride Request Broadcasted! Campus riders heading to $dropoff will be notified (৳${customFare.toInt()}).',
                  style: AppTypography.labelMd.copyWith(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error posting request: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag indicator
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.existingRequest != null ? 'Edit Ride Request' : 'Request a Bike Ride',
                      style: AppTypography.headlineSm.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF141416),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.existingRequest != null ? 'Update your destination, route or proposed fare' : 'Broadcast your destination to peer riders',
                      style: AppTypography.labelSm.copyWith(color: const Color(0xFF8E8E93)),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.two_wheeler, size: 14, color: Color(0xFFE65100)),
                      SizedBox(width: 4),
                      Text(
                        '1 Passenger',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFE65100),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Pickup Input with Google Autocomplete & Map Picker
            LocationAutocompleteInput(
              controller: _pickupController,
              labelText: 'PICKUP LOCATION',
              hintText: 'e.g. DIU Main Gate 1, AB-4, Daffodil Tower...',
              prefixIcon: Icons.trip_origin,
              prefixColor: const Color(0xFF2E7D32),
              onLocationSelected: (loc) {
                _pickupController.text = loc.title;
              },
              onGpsTap: () {
                _pickupController.text = 'DIU Smart City, Ashulia';
              },
            ),
            const SizedBox(height: 14),

            // Dropoff Input with Google Places Autocomplete & Map Picker
            LocationAutocompleteInput(
              controller: _dropoffController,
              labelText: 'WHERE DO YOU WANT TO GO?',
              hintText: 'e.g. Motijheel, Uttara, Mirpur 10, Dhanmondi...',
              prefixIcon: Icons.location_on,
              prefixColor: const Color(0xFFE65100),
              onLocationSelected: (loc) {
                _dropoffController.text = loc.title;
              },
            ),
            const SizedBox(height: 8),

            // Quick Hubs
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _quickDestinations.map((dest) {
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _dropoffController.text = dest;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.black.withOpacity(0.08)),
                    ),
                    child: Text(
                      dest,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Preferred Departure Time (Manual Entry & Quick Presets)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'PREFERRED TIME (MANUAL ENTRY / PICK)',
                  style: AppTypography.labelSm.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF8E8E93),
                    fontSize: 11,
                  ),
                ),
                GestureDetector(
                  onTap: _pickCustomTimeAndDate,
                  child: const Row(
                    children: [
                      Icon(Icons.calendar_month, size: 14, color: Color(0xFFE65100)),
                      SizedBox(width: 4),
                      Text(
                        'Date/Time Picker',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFE65100)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF2F2F7),
                borderRadius: BorderRadius.circular(14),
              ),
              child: TextField(
                controller: _timeController,
                onChanged: (val) => setState(() => _selectedTime = val),
                decoration: InputDecoration(
                  hintText: 'e.g. 10:30 AM, Right Now, Leaving 4:15 PM...',
                  prefixIcon: const Icon(Icons.access_time_filled, size: 18, color: Color(0xFFE65100)),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.edit_calendar, color: Color(0xFFE65100), size: 20),
                    onPressed: _pickCustomTimeAndDate,
                    tooltip: 'Pick Date & Time',
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _quickTimes.map((t) {
                final isSelected = _timeController.text == t;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedTime = t;
                      _timeController.text = t;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      t,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? Colors.white : const Color(0xFF3A3A3C),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Proposed Fuel Share Fare (Manual Entry & Quick Buttons)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'PROPOSED FARE (CUSTOM MANUAL AMOUNT)',
                  style: AppTypography.labelSm.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF8E8E93),
                    fontSize: 11,
                  ),
                ),
                Text(
                  '৳${(double.tryParse(_fareController.text) ?? _proposedFare).toInt()}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFE65100),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF4F5F7),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFFCC80), width: 1.2),
              ),
              child: TextField(
                controller: _fareController,
                keyboardType: TextInputType.number,
                onChanged: (val) {
                  setState(() {
                    _proposedFare = double.tryParse(val) ?? _proposedFare;
                  });
                },
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF141416)),
                decoration: const InputDecoration(
                  prefixIcon: Padding(
                    padding: EdgeInsets.only(left: 14, right: 8, top: 12),
                    child: Text(
                      '৳',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFFE65100)),
                    ),
                  ),
                  hintText: 'Enter custom fare amount (e.g. 35, 60, 100...)',
                  hintStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.normal, color: Colors.grey),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [35.0, 40.0, 50.0, 60.0, 75.0, 90.0, 100.0].map((f) {
                final currentFare = double.tryParse(_fareController.text) ?? _proposedFare;
                final isSel = currentFare == f;
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _proposedFare = f;
                        _fareController.text = f.toInt().toString();
                      });
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      decoration: BoxDecoration(
                        color: isSel ? const Color(0xFFE65100) : const Color(0xFFF4F5F7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '৳${f.toInt()}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isSel ? Colors.white : const Color(0xFF3A3A3C),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 22),

            // Submit Button (Obsidian Dark Button Matching Reference 2)
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submitRequest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF141416),
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.send_rounded, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            widget.existingRequest != null ? 'Save Changes (৳${(double.tryParse(_fareController.text) ?? _proposedFare).toInt()})' : 'Post Request (৳${(double.tryParse(_fareController.text) ?? _proposedFare).toInt()})',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
