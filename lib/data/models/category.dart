/// A user-editable event/task category.
class Category {
  const Category({
    required this.id,
    required this.name,
    required this.colorValue,
    this.icon = 'label',
    this.sortOrder = 0,
  });

  final String id;
  final String name;
  final int colorValue;

  /// Key into the category icon catalogue (see `category_icons.dart`).
  final String icon;
  final int sortOrder;

  Category copyWith({String? name, int? colorValue, String? icon, int? sortOrder}) =>
      Category(
        id: id,
        name: name ?? this.name,
        colorValue: colorValue ?? this.colorValue,
        icon: icon ?? this.icon,
        sortOrder: sortOrder ?? this.sortOrder,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'color': colorValue,
        'icon': icon,
        'sort_order': sortOrder,
      };

  factory Category.fromMap(Map<String, Object?> m) => Category(
        id: m['id'] as String,
        name: (m['name'] as String?) ?? '',
        colorValue: (m['color'] as num?)?.toInt() ?? 0xFF607D8B,
        icon: (m['icon'] as String?) ?? 'label',
        sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
      );

  /// Categories created on first launch.
  static const List<Category> defaults = [
    Category(id: 'cat_work', name: 'Work', colorValue: 0xFF3F6FD8, icon: 'work', sortOrder: 0),
    Category(id: 'cat_personal', name: 'Personal', colorValue: 0xFF7B5CD6, icon: 'person', sortOrder: 1),
    Category(id: 'cat_family', name: 'Family', colorValue: 0xFFE0703C, icon: 'family', sortOrder: 2),
    Category(id: 'cat_school', name: 'School', colorValue: 0xFF2E9E8F, icon: 'school', sortOrder: 3),
    Category(id: 'cat_health', name: 'Health', colorValue: 0xFFD6455D, icon: 'health', sortOrder: 4),
    Category(id: 'cat_travel', name: 'Travel', colorValue: 0xFF1E97C9, icon: 'travel', sortOrder: 5),
    Category(id: 'cat_birthday', name: 'Birthday', colorValue: 0xFFD457A6, icon: 'cake', sortOrder: 6),
    Category(id: 'cat_holiday', name: 'Holiday', colorValue: 0xFF4C9F50, icon: 'holiday', sortOrder: 7),
    Category(id: 'cat_other', name: 'Other', colorValue: 0xFF6B7684, icon: 'label', sortOrder: 8),
  ];
}
