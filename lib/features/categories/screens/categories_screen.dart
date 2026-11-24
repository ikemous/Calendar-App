import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/utilities/id.dart';
import '../../../data/models/category.dart';
import '../../../shared/utilities/event_style.dart';
import '../../../shared/widgets/common.dart';
import '../providers/categories_provider.dart';
import '../widgets/category_picker.dart';

/// Create, rename, recolour and delete categories.
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, Category? existing) async {
    final categories = ref.read(categoriesProvider);
    final result = await showDialog<Category>(
      context: context,
      builder: (context) => _CategoryDialog(
        existing: existing,
        nextSortOrder: categories.isEmpty
            ? 0
            : categories.map((c) => c.sortOrder).reduce((a, b) => a > b ? a : b) + 1,
        takenNames: {
          for (final c in categories)
            if (c.id != existing?.id) c.name.toLowerCase(),
        },
      ),
    );
    if (result != null) await ref.read(categoriesProvider.notifier).save(result);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Category c) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete "${c.name}"?',
      message: 'Events and tasks in this category are kept and become '
          'uncategorised.',
    );
    if (ok) await ref.read(categoriesProvider.notifier).delete(c.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: FloatingActionButton.extended(
        // Each tab has its own button; unique tags stop them animating
        // into each other when a page opens on top.
        heroTag: 'fab-categories',
        icon: const Icon(Icons.add),
        label: const Text('New category'),
        onPressed: () => _edit(context, ref, null),
      ),
      body: ContentWidth(
        child: categories.isEmpty
            ? const EmptyState(
                icon: Icons.label_outline,
                title: 'No categories',
                message: 'Create one to colour-code your events.',
              )
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 96),
                itemCount: categories.length,
                itemBuilder: (context, i) {
                  final c = categories[i];
                  return ListTile(
                    leading: CategoryBadge(category: c, size: 36),
                    title: Text(c.name),
                    onTap: () => _edit(context, ref, c),
                    trailing: IconButton(
                      tooltip: 'Delete ${c.name}',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _delete(context, ref, c),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({
    required this.existing,
    required this.nextSortOrder,
    required this.takenNames,
  });

  final Category? existing;
  final int nextSortOrder;
  final Set<String> takenNames;

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late int _color = widget.existing?.colorValue ?? appPalette.first;
  late String _icon = widget.existing?.icon ?? 'label';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final existing = widget.existing;
    Navigator.of(context).pop(existing == null
        ? Category(
            id: newId(),
            name: _name.text.trim(),
            colorValue: _color,
            icon: _icon,
            sortOrder: widget.nextSortOrder,
          )
        : existing.copyWith(
            name: _name.text.trim(), colorValue: _color, icon: _icon));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AlertDialog(
      title: Text(widget.existing == null ? 'New category' : 'Edit category'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _name,
                  autofocus: widget.existing == null,
                  maxLength: 30,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (v) {
                    final name = (v ?? '').trim();
                    if (name.isEmpty) return 'Enter a name';
                    if (widget.takenNames.contains(name.toLowerCase())) {
                      return 'A category with this name already exists';
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 8),
                Text('Colour', style: theme.textTheme.labelLarge),
                const SizedBox(height: 10),
                ColorSwatchPicker(
                  selected: _color,
                  onSelected: (c) => setState(() => _color = c),
                ),
                const SizedBox(height: 20),
                Text('Icon', style: theme.textTheme.labelLarge),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in categoryIcons.entries)
                      Semantics(
                        button: true,
                        selected: entry.key == _icon,
                        label: '${entry.key} icon',
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => setState(() => _icon = entry.key),
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: entry.key == _icon
                                  ? Color(_color)
                                  : scheme.surfaceContainerHighest,
                            ),
                            child: Icon(
                              entry.value,
                              size: 22,
                              color: entry.key == _icon
                                  ? onColor(Color(_color))
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
