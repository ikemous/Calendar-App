import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/services/app_services.dart';
import '../../../shared/widgets/common.dart';
import '../../calendar/widgets/item_tiles.dart';
import '../../categories/providers/categories_provider.dart';
import '../../events/providers/events_provider.dart';
import '../../tasks/providers/tasks_provider.dart';
import '../services/search_service.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = SearchService.search(
      query: _query,
      events: ref.watch(eventsProvider),
      tasks: [...ref.watch(tasksProvider)]..sort(compareTasks),
      categories: ref.watch(categoryMapProvider),
      now: ref.watch(clockProvider)(),
    );

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: TextField(
          controller: _controller,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search events and tasks',
            prefixIcon: const Icon(Icons.search),
            isDense: true,
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _controller.clear();
                      setState(() => _query = '');
                    },
                  ),
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
      ),
      body: ContentWidth(
        child: _query.trim().isEmpty
            ? const EmptyState(
                icon: Icons.search,
                title: 'Search your calendar',
                message:
                    'Find events and tasks by title, description, location or category.',
              )
            : results.isEmpty
                ? EmptyState(
                    icon: Icons.search_off,
                    title: 'No results',
                    message: 'Nothing matches "${_query.trim()}".',
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 32),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    children: [
                      if (results.events.isNotEmpty)
                        SectionHeader(
                          'Events · ${results.events.length}',
                          padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
                        ),
                      for (final o in results.events)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: EventTile(
                            occurrence: o,
                            day: o.start,
                            showDate: true,
                          ),
                        ),
                      if (results.tasks.isNotEmpty)
                        SectionHeader(
                          'Tasks · ${results.tasks.length}',
                          padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
                        ),
                      for (final t in results.tasks)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: TaskTile(task: t),
                        ),
                    ],
                  ),
      ),
    );
  }
}
