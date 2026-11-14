import 'package:flutter/foundation.dart';

import 'bridge_scope.dart';
import 'dependency_descriptor.dart';

/// A directed edge in the dependency graph: [from] waits on [to].
@immutable
final class DependencyEdge {
  /// Creates a [DependencyEdge].
  const DependencyEdge({required this.from, required this.to});

  /// The registration that declares the dependency.
  final DependencyInfo from;

  /// The dependency being waited on.
  final DependencyKey to;

  @override
  String toString() => '${from.key} -> $to';
}

/// Immutable snapshot of the container's `dependsOn` dependency graph.
///
/// Built from [DependencyInfo] snapshots across the root registry and all
/// live scopes. [cycles] lists every dependency cycle found (each cycle is a
/// list of node ids in resolution order); an empty list means the graph is
/// acyclic.
@immutable
final class BridgeDependencyGraph {
  /// Creates a [BridgeDependencyGraph].
  const BridgeDependencyGraph({
    required this.nodes,
    required this.edges,
    required this.cycles,
  });

  /// All known registrations (root + live scopes).
  final List<DependencyInfo> nodes;

  /// All declared `dependsOn` edges.
  final List<DependencyEdge> edges;

  /// Detected dependency cycles; each entry is a list of node ids.
  final List<List<String>> cycles;

  /// Whether the graph contains at least one cycle.
  bool get hasCycles => cycles.isNotEmpty;

  /// Node id used for cycle reporting: `scopeName|type|name`.
  static String nodeId(DependencyInfo info) {
    final scope = info.scopeName ?? 'root';
    final type = info.key.type.toString();
    final name = info.key.name == null ? '' : ':${info.key.name}';
    return '$scope|$type$name';
  }

  /// Returns the dependencies declared by [info] that are also registered.
  List<DependencyKey> dependenciesOf(DependencyInfo info) =>
      List.unmodifiable(info.dependsOn);

  @override
  String toString() =>
      'BridgeDependencyGraph(nodes: ${nodes.length}, edges: ${edges.length}, '
      'cycles: ${cycles.length})';
}
