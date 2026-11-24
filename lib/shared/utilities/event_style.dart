import 'package:material_ui/material_ui.dart';

import '../../data/models/app_settings.dart';
import '../../data/models/calendar_event.dart';
import '../../data/models/category.dart';

/// Colour an event is drawn in: its own colour, else its category's, else
/// the default event colour, else the accent colour.
Color eventColor(
  CalendarEvent event,
  Map<String, Category> categories,
  AppSettings settings,
) =>
    Color(event.colorValue ??
        categories[event.categoryId]?.colorValue ??
        settings.defaultEventColor ??
        settings.seedColor);

/// Readable text colour on top of [background].
Color onColor(Color background) =>
    ThemeData.estimateBrightnessForColor(background) == Brightness.dark
        ? Colors.white
        : const Color(0xFF1B1B1F);

Color priorityColor(Priority p, ColorScheme scheme) => switch (p) {
      Priority.high => scheme.error,
      Priority.medium => const Color(0xFFD9A21B),
      Priority.low => scheme.primary,
      Priority.none => scheme.outline,
    };

/// Icons that can be assigned to a category. Keys are what gets stored.
/// (A constant map keeps icon tree-shaking working in release builds.)
const Map<String, IconData> categoryIcons = {
  'label': Icons.label_outline,
  'work': Icons.work_outline,
  'person': Icons.person_outline,
  'family': Icons.family_restroom,
  'school': Icons.school_outlined,
  'health': Icons.favorite_outline,
  'travel': Icons.flight_outlined,
  'cake': Icons.cake_outlined,
  'holiday': Icons.celebration_outlined,
  'home': Icons.home_outlined,
  'sports': Icons.fitness_center,
  'food': Icons.restaurant_outlined,
  'shopping': Icons.shopping_bag_outlined,
  'money': Icons.payments_outlined,
  'music': Icons.music_note_outlined,
  'pet': Icons.pets_outlined,
  'car': Icons.directions_car_outlined,
  'star': Icons.star_outline,
  'book': Icons.menu_book_outlined,
  'call': Icons.call_outlined,
};

IconData categoryIcon(String? key) =>
    categoryIcons[key] ?? Icons.label_outline;
