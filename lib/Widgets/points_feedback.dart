import 'package:flutter/material.dart';

class AnimatedPointsText extends StatefulWidget {
  final int value;
  final TextStyle style;
  final String prefix;
  final String suffix;
  final Duration duration;

  const AnimatedPointsText({
    super.key,
    required this.value,
    required this.style,
    this.prefix = '',
    this.suffix = '',
    this.duration = const Duration(milliseconds: 700),
  });

  @override
  State<AnimatedPointsText> createState() => _AnimatedPointsTextState();
}

class _AnimatedPointsTextState extends State<AnimatedPointsText> {
  late int _previousValue;

  @override
  void initState() {
    super.initState();
    _previousValue = widget.value;
  }

  @override
  void didUpdateWidget(covariant AnimatedPointsText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _previousValue = oldWidget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(
        begin: _previousValue.toDouble(),
        end: widget.value.toDouble(),
      ),
      duration: widget.duration,
      builder: (context, value, _) {
        return Text(
          '${widget.prefix}${value.round()}${widget.suffix}',
          style: widget.style,
        );
      },
    );
  }
}

class PointsDeltaOverlay {
  static OverlayEntry show(
    BuildContext context, {
    required int delta,
    Offset? anchor,
    Duration duration = const Duration(milliseconds: 1300),
  }) {
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (_) => _PointsDeltaBubble(
        delta: delta,
        anchor: anchor,
        duration: duration,
      ),
    );

    overlay.insert(entry);

    Future.delayed(duration, () {
      entry.remove();
    });

    return entry;
  }
}

class _PointsDeltaBubble extends StatefulWidget {
  final int delta;
  final Offset? anchor;
  final Duration duration;

  const _PointsDeltaBubble({
    required this.delta,
    required this.anchor,
    required this.duration,
  });

  @override
  State<_PointsDeltaBubble> createState() => _PointsDeltaBubbleState();
}

class _PointsDeltaBubbleState extends State<_PointsDeltaBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _translateY;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..forward();

    _opacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.25, curve: Curves.easeOut),
      ),
    );

    _translateY = Tween<double>(begin: 10, end: -26).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ),
    );

    _scale = Tween<double>(begin: 0.94, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutBack,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final positive = widget.delta >= 0;
    final label = '${positive ? '+' : '-'}${widget.delta.abs()} XP';

    final media = MediaQuery.of(context);
    final resolvedAnchor = widget.anchor ??
        Offset(
          media.size.width - 92,
          media.padding.top + 54,
        );

    return IgnorePointer(
      child: Positioned(
        left: resolvedAnchor.dx - 50,
        top: resolvedAnchor.dy,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Opacity(
              opacity: _opacity.value.clamp(0, 1),
              child: Transform.translate(
                offset: Offset(0, _translateY.value),
                child: Transform.scale(
                  scale: _scale.value,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xEE111214),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: positive
                            ? const Color(0xFF4CAF50)
                            : const Color(0xFFE57373),
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 12,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: positive
                            ? const Color(0xFF81C784)
                            : const Color(0xFFFF8A80),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}