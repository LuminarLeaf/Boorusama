// Dart imports:
import 'dart:math';

// Flutter imports:
import 'package:flutter/material.dart';

/// Fallback max zoom scale when content size is unknown. Limits zoom-in.
const _kFallbackMaxScale = 10.0;

/// Fallback min zoom scale when content size is unknown. Limits zoom-out.
const _kFallbackMinScale = 0.6;

/// Multiplier to adjust max zoom based on the ratio between content and container sizes.
const _kScaleMultiplier = 5.0;

/// Default zoom scale for double tap if content and container sizes are unknown.
const _kDoubleTapScale = 3.0;

/// Factor to determine when content is much larger than the container.
const _kImageExceedsContainerThreshold = 3.0;

class InteractiveViewerExtended extends StatefulWidget {
  const InteractiveViewerExtended({
    required this.child,
    super.key,
    this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.controller,
    this.onZoomUpdated,
    this.enable = true,
    this.contentSize,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onLongPress;
  final void Function(bool zoomed)? onZoomUpdated;
  final TransformationController? controller;

  // This is needed to keep the state of the child widget, remove this widget will cause its child to be recreated
  final bool enable;

  // The intrinsic size (e.g. resolution) of the content
  final Size? contentSize;

  @override
  State<InteractiveViewerExtended> createState() =>
      _InteractiveViewerExtendedState();
}

class _InteractiveViewerExtendedState extends State<InteractiveViewerExtended>
    with SingleTickerProviderStateMixin {
  late var _controller = widget.controller ?? TransformationController();
  TapDownDetails? _doubleTapDetails;

  late final AnimationController _animationController;
  late Animation<Matrix4> _animation;

  late var enable = widget.enable;

  // Store the latest layout constraints.
  Size? _containerSize;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..addListener(_onAnimationChanged);

    _controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant InteractiveViewerExtended oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Handle controller changes
    if (oldWidget.controller != widget.controller) {
      _controller.removeListener(_onChanged);
      if (oldWidget.controller == null) {
        _controller.dispose();
      }

      final newController = widget.controller ?? TransformationController();
      _controller = newController;
      _controller.addListener(_onChanged);
    }

    if (oldWidget.enable != widget.enable) {
      setState(() {
        enable = widget.enable;
      });
    }
  }

  void _onAnimationChanged() => _controller.value = _animation.value;

  void _onChanged() {
    final clampedMatrix = Matrix4.diagonal3Values(
      _controller.value.right.x,
      _controller.value.up.y,
      _controller.value.forward.z,
    );

    widget.onZoomUpdated?.call(!clampedMatrix.isIdentity());
  }

  @override
  void dispose() {
    _animationController
      ..removeListener(_onAnimationChanged)
      ..dispose();

    _controller.removeListener(_onChanged);
    if (widget.controller == null) {
      _controller.dispose();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final containerSize = Size(
          constraints.maxWidth,
          constraints.maxHeight,
        );

        _containerSize = containerSize;

        return InteractiveViewer(
          minScale: _kFallbackMinScale,
          maxScale: _calcMaxScale(widget.contentSize, containerSize),
          transformationController: _controller,
          panEnabled: enable,
          scaleEnabled: enable,
          child: GestureDetector(
            onDoubleTapDown:
                enable ? (details) => _doubleTapDetails = details : null,
            onDoubleTap: enable
                ? () {
                    if (widget.onDoubleTap != null) {
                      widget.onDoubleTap!();
                    } else {
                      _handleDoubleTap();
                    }
                  }
                : null,
            onLongPress: enable ? widget.onLongPress : null,
            onTap: enable ? widget.onTap : null,
            child: widget.child,
          ),
        );
      },
    );
  }

  Matrix4 _calculateDoubleTapMatrix(Offset tapPosition) {
    // If already zoomed, reset transformation.
    if (!_controller.value.isIdentity()) {
      return Matrix4.identity();
    }

    final contentSize = widget.contentSize;
    final containerSize = _containerSize;

    // Check if both sizes are available.
    if (contentSize != null && containerSize != null) {
      final imageExceedsContainer = contentSize.width >
              (containerSize.width * _kImageExceedsContainerThreshold) ||
          contentSize.height >
              (containerSize.height * _kImageExceedsContainerThreshold);

      if (imageExceedsContainer) {
        return _calcZoomMatrixFromSize(
          containerSize: containerSize,
          contentSize: contentSize,
          focalPoint: tapPosition,
        );
      }
    }

    // Fallback to a fixed zoom.
    return _calcZoomMatrixFromZoomValue(
      focalPoint: tapPosition,
      zoomValue: _kDoubleTapScale,
    );
  }

  void _handleDoubleTap() {
    if (_doubleTapDetails == null) return;

    final position = _doubleTapDetails!.localPosition;
    final endMatrix = _calculateDoubleTapMatrix(position);

    _animation = Matrix4Tween(
      begin: _controller.value,
      end: endMatrix,
    ).animate(
      CurveTween(curve: Curves.easeInOut).animate(_animationController),
    );
    _animationController.forward(from: 0);
  }
}

// Calculates the target scale by fitting width for tall images and height for wide images.
Matrix4 _calcZoomMatrixFromSize({
  required Size containerSize,
  required Size contentSize,
  required Offset focalPoint,
}) {
  if (!_isValidSize(contentSize) || !_isValidSize(containerSize)) {
    return Matrix4.identity();
  }

  // Calculate the scale so that the content's width or height matches the container.
  final scale = max(
    contentSize.width / containerSize.width,
    contentSize.height / containerSize.height,
  );

  final translation = _calculateCenteringTranslation(
    containerSize: containerSize,
    tapPosition: focalPoint,
    scale: scale,
  );

  return Matrix4.identity()
    ..translate(translation.dx, translation.dy)
    ..scale(scale);
}

Matrix4 _calcZoomMatrixFromZoomValue({
  required Offset focalPoint,
  required double zoomValue,
}) {
  return Matrix4.identity()
    ..translate(focalPoint.dx, focalPoint.dy)
    ..scale(zoomValue)
    ..translate(-focalPoint.dx, -focalPoint.dy);
}

double _calcMaxScale(Size? contentSize, Size containerSize) {
  if (contentSize == null) {
    return _kFallbackMaxScale;
  }

  if (!_isValidSize(contentSize) || !_isValidSize(containerSize)) {
    return _kFallbackMaxScale;
  }

  return max(
        contentSize.width / containerSize.width,
        contentSize.height / containerSize.height,
      ) *
      _kScaleMultiplier;
}

// Utility function to calculate the translation needed to center the scaled tap position.
Offset _calculateCenteringTranslation({
  required Size containerSize,
  required Offset tapPosition,
  required double scale,
}) {
  final containerCenter = containerSize.center(Offset.zero);
  final scaledTap = tapPosition * scale;
  return containerCenter - scaledTap;
}

bool _isValidSize(Size? size) =>
    size != null && size.width != 0 && size.height != 0;
