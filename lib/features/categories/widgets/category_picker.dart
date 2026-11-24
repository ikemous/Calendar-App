import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/models/category.dart';
import '../../../shared/utilities/event_style.dart';
import '../providers/categories_provider.dart';

/// Result of the category picker. [id] null means "no category".
class CategoryChoice {
  const CategoryChoice(this.id);
  final String? id;
}

/// Round coloured badge with the category's icon.
class CategoryBadge extends StatelessWidget {
  const CategoryBadge({super.key, required this.category, this.size = 32});
  final Category? category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = category == null
        ? scheme.surfaceContainerHighest
        : Color(category!.colorValue);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(
        category == null ? Icons.label_off_outlined : categoryIcon(category!.icon),
        size: size * 0.56,
        color: category == null ? scheme.onSurfaceVariant : onColor(color),
      ),
    );
  }
}

Future<CategoryChoice?> pickCategory(
  BuildContext context,
  WidgetRef ref, {
  required String? selectedId,
}) {
  final categories = ref.read(categoriesProvider);
  return showDialog<CategoryChoice>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Category'),
      children: [
        ListTile(
          leading: const CategoryBadge(category: null),
          title: const Text('None'),
          selected: selectedId == null,
          onTap: () => Navigator.of(context).pop(const CategoryChoice(null)),
        ),
        for (final c in categories)
          ListTile(
            leading: CategoryBadge(category: c),
            title: Text(c.name),
            selected: c.id == selectedId,
            trailing: c.id == selectedId ? const Icon(Icons.check) : null,
            onTap: () => Navigator.of(context).pop(CategoryChoice(c.id)),
          ),
      ],
    ),
  );
}
