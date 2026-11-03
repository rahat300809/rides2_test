import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/utils/gps_location_service.dart';
import 'package:diu_ride/core/services/location_search_service.dart';
import 'package:diu_ride/core/providers/app_mode_provider.dart';

/// Clean, Minimal Commute Hub Card (Sunset Orange & White Theme)
/// Features:
/// - Connected route inputs (● Pickup Point ➔ ■ Where to? with GPS locate & swap)
/// - Inline autocomplete location suggestions dropdown
/// - Single departure schedule button (Default: ⚡ Leaving Right Now • Tap to schedule)
/// - Solid primary action button (Find Shared Rides on Route / Publish Shared Ride)
class UnifiedCommuteCard extends ConsumerStatefulWidget {
  final String initialPickup;
  final String initialDropoff;
  final VoidCallback onShowLocationPicker;
  final Function({
    required String pickup,
    required String dropoff,
    required DateTime departureTime,
    required bool isNow,
  }) onPassengerSearch;
  final Function({
    required String pickup,
    required String dropoff,
    required DateTime departureTime,
    required bool isNow,
  }) onRiderOfferProceed;
  final VoidCallback? onPostCustomRequest;
  final VoidCallback? onBrowseStudentGigs;

  const UnifiedCommuteCard({
    super.key,
    this.initialPickup = 'DIU Smart City, Ashulia',
    this.initialDropoff = '',
    required this.onShowLocationPicker,
    required this.onPassengerSearch,
    required this.onRiderOfferProceed,
    this.onPostCustomRequest,
    this.onBrowseStudentGigs,
  });

  @override
  ConsumerState<UnifiedCommuteCard> createState() => _UnifiedCommuteCardState();
}

class _UnifiedCommuteCardState extends ConsumerState<UnifiedCommuteCard> {
  late TextEditingController _pickupController;
  late TextEditingController _dropoffController;
  late FocusNode _dropFocusNode;
  DateTime _selectedTime = DateTime.now();
  bool _isNow = true;
  bool _isLocatingGps = false;

  List<LocationSearchResult> _suggestions = [];
  bool _showSuggestions = false;
  String _activeFocusField = 'dropoff';

  @override
  void initState() {
    super.initState();
    _dropFocusNode = FocusNode();
    _pickupController = TextEditingController(text: widget.initialPickup);
    _dropoffController = TextEditingController(text: widget.initialDropoff);
  }

  @override
  void didUpdateWidget(covariant UnifiedCommuteCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialPickup != oldWidget.initialPickup) {
      _pickupController.text = widget.initialPickup;
    }
    if (widget.initialDropoff != oldWidget.initialDropoff && widget.initialDropoff.isNotEmpty) {
      _dropoffController.text = widget.initialDropoff;
    }
  }

  @override
  void dispose() {
    _dropFocusNode.dispose();
    _pickupController.dispose();
    _dropoffController.dispose();
    super.dispose();
  }

  void _onTextChanged(String text, String field) {
    setState(() => _activeFocusField = field);
    final clean = text.trim();
    if (clean.isEmpty) {
      setState(() {
        _suggestions = LocationSearchService.campusLandmarks.take(6).toList();
        _showSuggestions = true;
      });
      return;
    }
    LocationSearchService.search(clean).then((results) {
      if (mounted) {
        setState(() {
          _suggestions = results.take(7).toList();
          _showSuggestions = results.isNotEmpty;
        });
      }
    });
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedTime.isAfter(now) ? _selectedTime : now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFE65100),
              onPrimary: Colors.white,
              onSurface: Color(0xFF1E293B),
            ),
          ),
          child: child!,
        );
      },
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedTime),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFE65100),
              onPrimary: Colors.white,
              onSurface: Color(0xFF1E293B),
            ),
          ),
          child: child!,
        );
      },
    );
    if (pickedTime == null || !mounted) return;

    setState(() {
      _selectedTime = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
      _isNow = false;
    });
  }

  void _swapLocations() {
    HapticFeedback.lightImpact();
    setState(() {
      final temp = _pickupController.text;
      _pickupController.text = _dropoffController.text;
      _dropoffController.text = temp;
    });
  }

  void _locateUserGps() async {
    HapticFeedback.mediumImpact();
    setState(() => _isLocatingGps = true);
    try {
      final name = await GpsLocationService.getReadableCurrentLocationName();
      if (mounted) {
        setState(() {
          _pickupController.text = name;
        });
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.my_location_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text('Pickup set to $name')),
              ],
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF16A34A),
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _pickupController.text = GpsLocationService.defaultCampusName);
    } finally {
      if (mounted) setState(() => _isLocatingGps = false);
    }
  }

  void _triggerPrimaryAction(bool isRider) {
    HapticFeedback.selectionClick();
    final pickup = _pickupController.text.trim().isEmpty ? 'DIU Smart City, Ashulia' : _pickupController.text.trim();
    final dropoff = _dropoffController.text.trim();

    if (isRider) {
      widget.onRiderOfferProceed(
        pickup: pickup,
        dropoff: dropoff,
        departureTime: _isNow ? DateTime.now() : _selectedTime,
        isNow: _isNow,
      );
    } else {
      widget.onPassengerSearch(
        pickup: pickup,
        dropoff: dropoff,
        departureTime: _isNow ? DateTime.now() : _selectedTime,
        isNow: _isNow,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final appMode = ref.watch(appModeProvider);
    final isRider = appMode.isRider;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
          BoxShadow(
            color: const Color(0xFFE65100).withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: const Color(0xFFF1F5F9),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Connected Route Input Box (Pickup Point ● ➔ Where are you going? ■)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE2E8F0), width: 1.1),
              ),
              child: Stack(
                children: [
                  Column(
                    children: [
                      // Pickup Location Row
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 11, 48, 9),
                        child: Row(
                          children: [
                            // Dot (●)
                            Container(
                              width: 14,
                              height: 14,
                              decoration: const BoxDecoration(
                                color: Color(0xFF0F172A),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Container(
                                  width: 5,
                                  height: 5,
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Text(
                                        'Pickup Point',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w500,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      GestureDetector(
                                        onTap: _isLocatingGps ? null : _locateUserGps,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFEFF6FF),
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(color: const Color(0xFFBFDBFE), width: 0.8),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (_isLocatingGps)
                                                const SizedBox(
                                                  width: 10,
                                                  height: 10,
                                                  child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF2563EB)),
                                                )
                                              else
                                                const Icon(Icons.my_location_rounded, size: 11, color: Color(0xFF2563EB)),
                                              const SizedBox(width: 4),
                                              Text(
                                                _isLocatingGps ? 'Locating...' : 'Auto GPS / Map',
                                                style: const TextStyle(
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: Color(0xFF2563EB),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  TextField(
                                    controller: _pickupController,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF0F172A),
                                    ),
                                    decoration: const InputDecoration(
                                      hintText: 'Enter pickup location...',
                                      hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.normal),
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(vertical: 3),
                                      border: InputBorder.none,
                                    ),
                                    onChanged: (val) => _onTextChanged(val, 'pickup'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Divider with connector cutout
                      const Divider(height: 1, indent: 42, endIndent: 16, color: Color(0xFFE2E8F0)),

                      // Dropoff Location Row
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 9, 48, 11),
                        child: Row(
                          children: [
                            // Square (■)
                            Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE65100),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Center(
                                child: Container(
                                  width: 5,
                                  height: 5,
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Where are you going?',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                  TextField(
                                    controller: _dropoffController,
                                    focusNode: _dropFocusNode,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF0F172A),
                                    ),
                                    decoration: InputDecoration(
                                      hintText: isRider ? 'Where to? e.g. Mirpur, Uttara Metro' : 'e.g. Mirpur 10, Uttara Metro',
                                      hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.normal),
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(vertical: 3),
                                      border: InputBorder.none,
                                      suffixIcon: _dropoffController.text.isNotEmpty
                                          ? GestureDetector(
                                              onTap: () {
                                                _dropoffController.clear();
                                                setState(() => _showSuggestions = false);
                                              },
                                              child: const Icon(Icons.cancel_rounded, size: 16, color: Color(0xFF94A3B8)),
                                            )
                                          : null,
                                    ),
                                    onChanged: (val) => _onTextChanged(val, 'dropoff'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Vertical connector line between ● and ■
                  Positioned(
                    left: 20,
                    top: 25,
                    bottom: 25,
                    child: Container(
                      width: 2,
                      decoration: BoxDecoration(
                        color: const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),

                  // GPS Locate icon on top row
                  Positioned(
                    right: 12,
                    top: 13,
                    child: Tooltip(
                      message: 'Set current location auto by GPS / Map',
                      child: GestureDetector(
                        onTap: _isLocatingGps ? null : _locateUserGps,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFBBF7D0), width: 1.2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.06),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: _isLocatingGps
                              ? const Center(
                                  child: SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF16A34A)),
                                  ),
                                )
                              : const Icon(Icons.my_location_rounded, size: 16, color: Color(0xFF15803D)),
                        ),
                      ),
                    ),
                  ),

                  // Route Swap icon on bottom row
                  Positioned(
                    right: 12,
                    bottom: 13,
                    child: GestureDetector(
                      onTap: _swapLocations,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.06),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.swap_vert_rounded, size: 17, color: Color(0xFFE65100)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Autocomplete Suggestions Dropdown
          if (_showSuggestions && _suggestions.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _suggestions.length > 5 ? 5 : _suggestions.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                  itemBuilder: (ctx, i) {
                    final item = _suggestions[i];
                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                      leading: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3E0),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.near_me_rounded, color: Color(0xFFE65100), size: 16),
                      ),
                      title: Text(
                        item.title,
                        style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13, color: Color(0xFF0F172A)),
                      ),
                      subtitle: Text(
                        item.subtitle,
                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                      ),
                      trailing: const Icon(Icons.north_west_rounded, size: 14, color: Color(0xFF94A3B8)),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        setState(() {
                          if (_activeFocusField == 'pickup') {
                            _pickupController.text = item.title;
                          } else {
                            _dropoffController.text = item.title;
                          }
                          _showSuggestions = false;
                        });
                      },
                    );
                  },
                ),
              ),
            ),

          // 2. Single Departure Schedule Button (Default: ⚡ Leaving Right Now • Tap to change)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                _pickDateTime();
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                decoration: BoxDecoration(
                  color: _isNow ? const Color(0xFFFFF3E0) : const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _isNow ? const Color(0xFFFFB74D) : const Color(0xFFE65100),
                    width: 1.2,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _isNow ? Icons.bolt_rounded : Icons.schedule_rounded,
                          size: 17,
                          color: const Color(0xFFE65100),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          _isNow
                              ? 'Leaving Right Now'
                              : '${_selectedTime.day}/${_selectedTime.month} at ${_selectedTime.hour % 12 == 0 ? 12 : _selectedTime.hour % 12}:${_selectedTime.minute.toString().padLeft(2, '0')} ${_selectedTime.hour >= 12 ? 'PM' : 'AM'}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFE65100),
                          ),
                        ),
                      ],
                    ),
                    if (_isNow)
                      const Row(
                        children: [
                          Text(
                            'Schedule later',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF94A3B8),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(Icons.edit_calendar_outlined, size: 14, color: Color(0xFF94A3B8)),
                        ],
                      )
                    else
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          setState(() {
                            _isNow = true;
                            _selectedTime = DateTime.now();
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE65100),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.close_rounded, size: 12, color: Colors.white),
                              SizedBox(width: 2),
                              Text('Reset to Now', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // 3. Solid Primary Action Button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: GestureDetector(
              onTap: () => _triggerPrimaryAction(isRider),
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE65100), Color(0xFFFF6D00)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x38E65100),
                      blurRadius: 14,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isRider ? Icons.two_wheeler_rounded : Icons.search_rounded,
                      color: Colors.white,
                      size: 19,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isRider ? 'Publish Shared Ride' : 'Find Shared Rides on Route',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 17),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
