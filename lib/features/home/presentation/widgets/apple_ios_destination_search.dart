import 'package:flutter/material.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/features/rides/data/models/ride_model.dart';

class AppleIosDestinationSearch extends StatefulWidget {
  final List<RideModel> allRides;
  final String currentQuery;
  final Function(String query) onQueryChanged;
  final Function(String destination) onDestinationSelected;
  final VoidCallback onClear;

  const AppleIosDestinationSearch({
    super.key,
    required this.allRides,
    required this.currentQuery,
    required this.onQueryChanged,
    required this.onDestinationSelected,
    required this.onClear,
  });

  @override
  State<AppleIosDestinationSearch> createState() => _AppleIosDestinationSearchState();
}

class _AppleIosDestinationSearchState extends State<AppleIosDestinationSearch> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  List<String> _suggestions = [];

  // Core DIU Hubs & Campus Spots
  static const List<String> _commonHubs = [
    'AB4 (Academic Building 4)',
    'DIU Main Gate 1',
    'Transport Terminal (Bus Bay)',
    'Uttara Sector 11 (House Building)',
    'Uttara North Metro Station (Diabari)',
    'Mirpur 10 Roundabout',
    'Dhanmondi 32 (Metro Station)',
    'Birulia Bridge Stand',
    'Savar City Centre',
    'Gazipur Chowrasta',
    'ECB Chattar (Airport Road)',
  ];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentQuery);
    _updateSuggestions(widget.currentQuery);
  }

  @override
  void didUpdateWidget(covariant AppleIosDestinationSearch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentQuery != _controller.text) {
      _controller.text = widget.currentQuery;
      _updateSuggestions(widget.currentQuery);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _updateSuggestions(String text) {
    final query = text.trim().toLowerCase();
    final Set<String> pooled = {};

    // Pool from active rides: BOTH Origin (From) AND Destination (To)
    for (final r in widget.allRides) {
      if (r.originName.isNotEmpty) pooled.add(r.originName);
      if (r.originSubtitle != null && r.originSubtitle!.isNotEmpty) {
        pooled.add(r.originSubtitle!);
      }
      if (r.destinationName.isNotEmpty) pooled.add(r.destinationName);
      if (r.destinationSubtitle != null && r.destinationSubtitle!.isNotEmpty) {
        pooled.add(r.destinationSubtitle!);
      }
    }
    // Add common hubs
    pooled.addAll(_commonHubs);

    if (query.isEmpty) {
      // Suggest top campus hubs & destinations
      setState(() {
        _suggestions = _commonHubs.take(5).toList();
      });
    } else {
      // If query mentions ab4, ensure AB4 is right at top
      final isAb4 = query.contains('ab4') || query.contains('ab 4') || query.contains('ab-4');

      // Filter dynamically across both From and To
      final matches = pooled
          .where((place) {
            final p = place.toLowerCase();
            if (isAb4 && (p.contains('ab4') || p.contains('academic building 4'))) return true;
            return p.contains(query);
          })
          .take(6)
          .toList();

      if (isAb4 && !matches.any((m) => m.toLowerCase().contains('ab4'))) {
        matches.insert(0, 'AB4 (Academic Building 4)');
      }

      // If no exact substring in pooled, still include query
      if (matches.isEmpty && query.length >= 2) {
        matches.add(text.trim());
      }

      setState(() {
        _suggestions = matches;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasText = _controller.text.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 3D Apple-Style Floating Search Bar (Matching Reference Mockups)
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: hasText ? const Color(0xFFE65100) : Colors.black.withOpacity(0.08),
                width: hasText ? 1.8 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: hasText
                      ? const Color(0xFFE65100).withOpacity(0.20)
                      : const Color(0x14000000),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
                const BoxShadow(
                  color: Colors.white,
                  blurRadius: 1,
                  offset: Offset(0, -1),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            child: Row(
              children: [
                // 3D Search Icon with Warm Sunset Amber Gradient
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFA000), Color(0xFFE65100)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFE65100).withOpacity(0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.search, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),

                // Text Input
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    style: AppTypography.bodyLgMedium.copyWith(
                      color: const Color(0xFF141416),
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search From / To (e.g. AB4, Uttara, Mirpur)...',
                      hintStyle: AppTypography.bodyMd.copyWith(
                        color: const Color(0xFF8E8E93),
                        fontWeight: FontWeight.w400,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onChanged: (val) {
                      _updateSuggestions(val);
                      widget.onQueryChanged(val);
                    },
                    onSubmitted: (val) {
                      if (val.trim().isNotEmpty) {
                        widget.onDestinationSelected(val.trim());
                      }
                    },
                  ),
                ),

                // Clear or Status button (Matching Reference 1 "Now" badge)
                if (hasText)
                  IconButton(
                    icon: const Icon(Icons.cancel, color: Color(0xFF8E8E93), size: 20),
                    onPressed: () {
                      _controller.clear();
                      _updateSuggestions('');
                      widget.onClear();
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F5F7),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.black.withOpacity(0.06)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.calendar_today, size: 13, color: Color(0xFF141416)),
                        SizedBox(width: 5),
                        Text(
                          'Now',
                          style: TextStyle(
                            color: Color(0xFF141416),
                            fontWeight: FontWeight.w800,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // Auto-Suggestions (Apple iOS 3D Chips / Pills) - Only shown when user is searching
          if (hasText && _suggestions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.auto_awesome, size: 13, color: Color(0xFFFFA000)),
                const SizedBox(width: 5),
                Text(
                  'Suggested destination matches:',
                  style: AppTypography.labelSm.copyWith(
                    color: Colors.white.withOpacity(0.95),
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: _suggestions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final item = _suggestions[index];
                  final isSelected = hasText &&
                      item.toLowerCase().contains(_controller.text.trim().toLowerCase());

                  return InkWell(
                    onTap: () {
                      _controller.text = item;
                      _updateSuggestions(item);
                      widget.onDestinationSelected(item);
                      _focusNode.unfocus();
                    },
                    borderRadius: BorderRadius.circular(18),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFFE65100) : Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFFE65100)
                              : Colors.black.withOpacity(0.08),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: isSelected
                                ? const Color(0xFFE65100).withOpacity(0.3)
                                : Colors.black.withOpacity(0.04),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.location_on,
                            size: 13,
                            color: isSelected ? Colors.white : const Color(0xFFE65100),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            item,
                            style: TextStyle(
                              color: isSelected ? Colors.white : const Color(0xFF141416),
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
