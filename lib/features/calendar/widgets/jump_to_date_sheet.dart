import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/config/app_config.dart';

/// Bottom sheet for jumping quickly to another month or year, with a
/// shortcut to the full date picker. Returns the chosen date.
Future<DateTime?> showJumpToDateSheet(BuildContext context, DateTime current) =>
    showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _JumpSheet(current: current),
    );

class _JumpSheet extends StatefulWidget {
  const _JumpSheet({required this.current});
  final DateTime current;

  @override
  State<_JumpSheet> createState() => _JumpSheetState();
}

class _JumpSheetState extends State<_JumpSheet> {
  late int _year = widget.current.year;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = DateTime.now();
    final minYear = AppConfig.minDate.year;
    final maxYear = AppConfig.maxDate.year;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      tooltip: 'Previous year',
                      onPressed: _year > minYear
                          ? () => setState(() => _year--)
                          : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Text('$_year', style: theme.textTheme.headlineSmall),
                    IconButton(
                      tooltip: 'Next year',
                      onPressed: _year < maxYear
                          ? () => setState(() => _year++)
                          : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                GridView.count(
                  crossAxisCount: 4,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.9,
                  children: [
                    for (var m = 1; m <= 12; m++)
                      _MonthButton(
                        label: DateFormat.MMM().format(DateTime(_year, m)),
                        selected: _year == widget.current.year &&
                            m == widget.current.month,
                        current: _year == now.year && m == now.month,
                        onTap: () => Navigator.of(context).pop(
                          _year == now.year && m == now.month
                              ? DateTime(now.year, now.month, now.day)
                              : DateTime(_year, m),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.edit_calendar_outlined),
                        label: const Text('Choose a date'),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: widget.current,
                            firstDate: AppConfig.minDate,
                            lastDate: AppConfig.maxDate,
                          );
                          if (picked != null && context.mounted) {
                            Navigator.of(context).pop(picked);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        icon: const Icon(Icons.today),
                        label: const Text('Today'),
                        style: FilledButton.styleFrom(
                          foregroundColor: scheme.onSecondaryContainer,
                        ),
                        onPressed: () => Navigator.of(context)
                            .pop(DateTime(now.year, now.month, now.day)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MonthButton extends StatelessWidget {
  const _MonthButton({
    required this.label,
    required this.selected,
    required this.current,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primary : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: current || selected ? FontWeight.w700 : FontWeight.w500,
              color: selected
                  ? scheme.onPrimary
                  : (current ? scheme.primary : scheme.onSurface),
            ),
          ),
        ),
      ),
    );
  }
}
