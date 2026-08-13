import 'package:flutter/material.dart';

import 'whatsapp_style.dart';

/// WhatsApp-style message bubble: a rounded box with the little corner tail
/// pointing towards the sender, plus tap/long-press support for actions.
class BubbleFrame extends StatelessWidget {
  const BubbleFrame({
    super.key,
    required this.fromMe,
    required this.bubbleColor,
    required this.child,
    this.onLongPress,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    this.constraints,
  });

  final bool fromMe;
  final Color bubbleColor;
  final Widget child;
  final VoidCallback? onLongPress;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final BoxConstraints? constraints;

  /// Largest bubble width (fraction of the screen), like WhatsApp.
  static BoxConstraints maxWidth(BuildContext context) => BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.85,
      );

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: fromMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 10),
          constraints: constraints ?? maxWidth(context),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: CustomPaint(
            painter: _BubbleTailPainter(color: bubbleColor, fromMe: fromMe),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// Draws the small triangular tail at the bubble's bottom sender corner.
class _BubbleTailPainter extends CustomPainter {
  const _BubbleTailPainter({required this.color, required this.fromMe});

  final Color color;
  final bool fromMe;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = color;
    final Path path = Path();
    const double tail = 8;
    final double w = size.width;
    final double h = size.height;
    if (fromMe) {
      path.moveTo(w - tail * 2, h - tail);
      path.lineTo(w - tail, h);
      path.lineTo(w, h - tail * 2);
    } else {
      path.moveTo(tail * 2, h - tail);
      path.lineTo(tail, h);
      path.lineTo(0, h - tail * 2);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BubbleTailPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.fromMe != fromMe;
}

/// Builds a bubble color for a message using the [WhatsAppStyle] palette.
Color bubbleColorFor(WhatsAppStyle style, bool fromMe) =>
    fromMe ? style.outgoingBubble : style.incomingBubble;
