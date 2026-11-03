import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';

class DefaultCommuteAddressCard extends ConsumerStatefulWidget {
  final Function(String selectedAddress)? onAddressSelectedForSearch;

  const DefaultCommuteAddressCard({
    super.key,
    this.onAddressSelectedForSearch,
  });

  @override
  ConsumerState<DefaultCommuteAddressCard> createState() => _DefaultCommuteAddressCardState();
}

class _DefaultCommuteAddressCardState extends ConsumerState<DefaultCommuteAddressCard> {
  static const List<String> _presetHubs = [
    'Uttara Sector 11 (House Building)',
    'Uttara North Metro (Diabari)',
    'Mirpur 10 Roundabout',
    'Dhanmondi 32 (Metro Station)',
    'Birulia Bridge Stand',
    'Savar City Centre',
    'Gazipur Chowrasta',
  ];

  void _openAddressSheet() {
    final currentAddress = ref.read(authNotifierProvider).user?.defaultAddress ?? '';
    final controller = TextEditingController(text: currentAddress);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 20,
                  offset: Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD1D1D6),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFFE65100), Color(0xFFF57C00)],
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.notifications_active, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Default Commute Address',
                            style: AppTypography.titleMd.copyWith(
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF1C1C1E),
                            ),
                          ),
                          Text(
                            'Get instant early alerts when peers offer bike rides',
                            style: AppTypography.labelSm.copyWith(
                              color: const Color(0xFF8E8E93),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Text field
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F4F7),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.black.withOpacity(0.06)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: TextField(
                    controller: controller,
                    autofocus: false,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    decoration: const InputDecoration(
                      hintText: 'Enter your commute address (e.g. Uttara)',
                      border: InputBorder.none,
                      icon: Icon(Icons.location_on, color: Color(0xFFE65100)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                Text(
                  'Quick Select Popular Hubs:',
                  style: AppTypography.labelSm.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF3A3A3C),
                  ),
                ),
                const SizedBox(height: 10),

                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _presetHubs.map((hub) {
                    return InkWell(
                      onTap: () {
                        controller.text = hub;
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F9FA),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.black.withOpacity(0.08)),
                        ),
                        child: Text(
                          hub,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1C1C1E),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),

                // Save button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () async {
                      final newAddress = controller.text.trim();
                      if (newAddress.isEmpty) return;

                      Navigator.of(ctx).pop();
                      final success = await ref
                          .read(authNotifierProvider.notifier)
                          .updateDefaultAddress(newAddress);

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: const Color(0xFF1C1C1E),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            content: Row(
                              children: [
                                const Icon(Icons.check_circle, color: Color(0xFF00C853)),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    success
                                        ? 'Default commute set to "$newAddress"! Early alerts active.'
                                        : 'Address saved locally.',
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF141416),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Save Default Address',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authNotifierProvider).user;
    final defaultAddr = user?.defaultAddress;
    final hasAddress = defaultAddr != null && defaultAddr.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFFFFF), Color(0xFFF9FBFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: hasAddress ? const Color(0xFFE65100).withOpacity(0.3) : Colors.black.withOpacity(0.06),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
            const BoxShadow(
              color: Colors.white,
              blurRadius: 1,
              offset: Offset(0, -1),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3E0),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.home_work_rounded, color: Color(0xFFE65100), size: 18),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Default Commute Base',
                          style: AppTypography.labelLg.copyWith(
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF1C1C1E),
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          'Early alert hub for peer bikes',
                          style: AppTypography.labelSm.copyWith(
                            color: const Color(0xFF8E8E93),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                InkWell(
                  onTap: _openAddressSheet,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      hasAddress ? 'Change' : 'Set Address',
                      style: const TextStyle(
                        color: Color(0xFFE65100),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Current Address Display
            InkWell(
              onTap: () {
                if (hasAddress && widget.onAddressSelectedForSearch != null) {
                  widget.onAddressSelectedForSearch!(defaultAddr);
                } else {
                  _openAddressSheet();
                }
              },
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F4F7),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.pin_drop, size: 18, color: Color(0xFFE65100)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        hasAddress ? defaultAddr : 'Tap to set default address (e.g. Uttara)',
                        style: TextStyle(
                          color: hasAddress ? const Color(0xFF1C1C1E) : const Color(0xFF8E8E93),
                          fontWeight: hasAddress ? FontWeight.w700 : FontWeight.w500,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (hasAddress)
                      const Icon(Icons.search, size: 16, color: Color(0xFFE65100)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Notification Status Badge
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: hasAddress ? const Color(0xFF00C853) : const Color(0xFFFF9500),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    hasAddress
                        ? '🔔 Early notifications active: You will be alerted first for rides to $defaultAddr'
                        : 'Set an address to receive early push alerts when peers share matching bikes',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: hasAddress ? const Color(0xFF2E7D32) : const Color(0xFF8E8E93),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
