import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/app_services.dart';
import '../../../data/models/category.dart';
import '../../events/providers/events_provider.dart';
import '../../sync/providers/sync_controller.dart';
import '../../tasks/providers/tasks_provider.dart';

class CategoriesNotifier extends Notifier<List<Category>> {
  @override
  List<Category> build() => ref.watch(bootstrapProvider).categories;

  Category? byId(String? id) {
    if (id == null) return null;
    for (final c in state) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> save(Category category) async {
    await ref.read(categoryRepositoryProvider).upsert(category);
    await ref.read(syncServiceProvider).recordChanged('categories', category.id);
    final exists = state.any((c) => c.id == category.id);
    state = exists
        ? [for (final c in state) c.id == category.id ? category : c]
        : [...state, category];
  }

  /// Deletes the category. Events and tasks that used it are kept and
  /// become uncategorised.
  Future<void> delete(String id) async {
    await ref.read(categoryRepositoryProvider).delete(id);
    await ref.read(syncServiceProvider).recordDeleted('categories', id);
    state = [
      for (final c in state)
        if (c.id != id) c,
    ];
    await ref.read(eventsProvider.notifier).reload();
    await ref.read(tasksProvider.notifier).reload();
  }

  Future<void> reload() async {
    state = await ref.read(categoryRepositoryProvider).getAll();
  }
}

final categoriesProvider =
    NotifierProvider<CategoriesNotifier, List<Category>>(CategoriesNotifier.new);

final categoryMapProvider = Provider<Map<String, Category>>(
  (ref) => {for (final c in ref.watch(categoriesProvider)) c.id: c},
);
