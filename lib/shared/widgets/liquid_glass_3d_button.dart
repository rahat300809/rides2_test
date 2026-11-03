import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A premium, tactile 3D Liquid Glassmorphic Button.
/// Features frosted glass refraction, multi-layered specular highlights,
/// dynamic 3D depth shadows, and interactive spring-like press physics.
class LiquidGlass3DButton extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;
  final double? width;
  final double height;
  final BorderRadius? borderRadius;
  final Gradient? gradient;
  final Color? backgroundColor;
  final Color? borderColor;
  final EdgeInsetsGeometry padding;
  final bool enableGlow;
  final Color glowColor;

  const LiquidGlass3DButton({
    super.key,
    required this.onTap,
    required this.child,
    this.width,
    this.height = 48,
    this.borderRadius,
    this.gradient,
    this.backgroundColor,
    this.borderColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
    this.enableGlow = true,
    this.glowColor = const Color(0xFFE65100),
  });

  @override
  State<LiquidGlass3DButton> createState() => _LiquidGlass3DButtonState();
}

class _LiquidGlass3DButtonState extends State<LiquidGlass3DButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.borderRadius ?? BorderRadius.circular(16);
    final baseGradient = widget.gradient ??
        const LinearGradient(
          colors: [Color(0xFFD84315), Color(0xFFFFA000)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );

    return GestureDetector(
      onTapDown: (_) {
        HapticFeedback.lightImpact();
        setState(() => _isPressed = true);
      },
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: r,
            boxShadow: [
              if (widget.enableGlow)
                BoxShadow(
                  color: widget.glowColor.withOpacity(_isPressed ? 0.18 : 0.35),
                  blurRadius: _isPressed ? 8 : 16,
                  offset: Offset(0, _isPressed ? 2 : 6),
                  spreadRadius: _isPressed ? -1 : 0,
                ),
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: r,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                padding: widget.padding,
                decoration: BoxDecoration(
                  borderRadius: r,
                  gradient: widget.backgroundColor != null ? null : baseGradient,
                  color: widget.backgroundColor,
                  border: Border.all(
                    color: widget.borderColor ?? Colors.white.withOpacity(0.65),
                    width: 1.2,
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Top-edge 3D Specular Sheen / Rim Reflection
                    Positioned(
                      top: 0,
                      left: 4,
                      right: 4,
                      height: 1.2,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withOpacity(0.1),
                              Colors.white.withOpacity(0.85),
                              Colors.white.withOpacity(0.1),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Subtly glazed top reflection highlight
                    Positioned(
                      top: 1,
                      left: 8,
                      right: 8,
                      height: widget.height * 0.45,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.vertical(top: Radius.circular(r.topLeft.x)),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withOpacity(0.25),
                              Colors.white.withOpacity(0.0),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Button Content
                    widget.child,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

