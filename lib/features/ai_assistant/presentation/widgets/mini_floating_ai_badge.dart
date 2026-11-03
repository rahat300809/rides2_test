import 'package:flutter/material.dart';
import 'package:diu_ride/features/ai_assistant/presentation/widgets/diu_ai_chat_sheet.dart';

/// Clean, high-contrast Support Center Floating Action Badge
/// Features a prominent Support Agent headset inside a crisp circular badge,
/// zero text clutter, ultra-lightweight for 120Hz smooth rendering.
class MiniFloatingAiBadge extends StatelessWidget {
  final bool showLabel;

  const MiniFloatingAiBadge({
    super.key,
    this.showLabel = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => DiuAiChatSheet.show(context),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFE65100), // Vibrant Sunset Orange
              Color(0xFFFF7A00), // Radiant Amber
            ],
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFE65100).withOpacity(0.40),
              blurRadius: 14,
              spreadRadius: 1,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // Crisp White Inner Disc for Maximum Logo Visibility
            Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x1F000000),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: const Center(
                child: Icon(
                  Icons.support_agent,
                  size: 25,
                  color: Color(0xFFE65100),
                ),
              ),
            ),

            // Active Online Green Indicator Dot
            Positioned(
              right: 3,
              top: 3,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: const Color(0xFF00E676),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x6600E676),
                      blurRadius: 4,
                      offset: Offset(0, 1),
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
