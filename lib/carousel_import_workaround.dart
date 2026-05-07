/// Carousel import workaround for Flutter 3.38+ + camerawesome 2.0.1 conflict
/// 
/// This file provides an unambiguous source for CarouselController to resolve
/// the conflict between package:carousel_slider and package:flutter Material carousel.

// Explicitly import from carousel_slider package, hiding any Flutter imports
import 'package:carousel_slider/carousel_controller.dart' as carousel_pkg;

// Re-export with unambiguous name
export 'package:carousel_slider/carousel_controller.dart' show CarouselController;
