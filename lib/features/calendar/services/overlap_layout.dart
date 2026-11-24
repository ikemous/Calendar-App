/// An item placed in a column of a time grid.
class Placed<T> {
  Placed(this.item, this.startMinute, this.endMinute, this.column);
  final T item;
  final int startMinute;
  final int endMinute;
  final int column;

  /// Number of side-by-side columns in this item's overlap group.
  int columns = 1;
}

/// Arranges items that overlap in time into side-by-side columns, the way
/// day and week views draw simultaneous events.
///
/// Items are grouped into clusters of transitively overlapping intervals;
/// every item in a cluster gets the same column count so widths line up.
List<Placed<T>> layoutOverlaps<T>(
  Iterable<T> items, {
  required int Function(T) startMinute,
  required int Function(T) endMinute,
  int minDuration = 20,
}) {
  final entries = [
    for (final i in items)
      (
        item: i,
        start: startMinute(i),
        end: endMinute(i) < startMinute(i) + minDuration
            ? startMinute(i) + minDuration
            : endMinute(i),
      ),
  ]..sort((a, b) {
      final c = a.start.compareTo(b.start);
      return c != 0 ? c : b.end.compareTo(a.end);
    });

  final result = <Placed<T>>[];
  var cluster = <Placed<T>>[];
  var columnEnds = <int>[];
  var clusterEnd = -1;

  void flush() {
    for (final p in cluster) {
      p.columns = columnEnds.length;
    }
    result.addAll(cluster);
    cluster = [];
    columnEnds = [];
  }

  for (final e in entries) {
    if (cluster.isNotEmpty && e.start >= clusterEnd) flush();
    var col = columnEnds.indexWhere((end) => end <= e.start);
    if (col == -1) {
      columnEnds.add(e.end);
      col = columnEnds.length - 1;
    } else {
      columnEnds[col] = e.end;
    }
    cluster.add(Placed(e.item, e.start, e.end, col));
    if (e.end > clusterEnd) clusterEnd = e.end;
  }
  flush();
  return result;
}
