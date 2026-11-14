import 'dart:async';

import '../exceptions/bridge_exceptions.dart';
import 'dependency_descriptor.dart';

/// A single in-flight dependency resolution step.
///
/// Frames form an async-local chain (via [Zone] values) so that circular
/// dependency detection works across synchronous factories, asynchronous
/// factories, and [BridgeScope] hierarchies alike.
final class ResolutionFrame {
  /// Creates a [ResolutionFrame].
  const ResolutionFrame({required this.owner, required this.key});

  /// The container or scope that owns the registration being resolved.
  final Object owner;

  /// The dependency key being resolved.
  final DependencyKey key;
}

final Object _resolutionChainZoneKey = Object();

/// The async-local chain of in-flight resolutions for the current execution
/// context. Zone values propagate across `await` boundaries, so concurrent
/// resolutions in unrelated async contexts never observe each other.
List<ResolutionFrame> get currentResolutionChain =>
    Zone.current[_resolutionChainZoneKey] as List<ResolutionFrame>? ??
    const <ResolutionFrame>[];

/// Runs [body] with [key] pushed onto the resolution chain for [owner].
///
/// Throws [BridgeCircularDependencyException] when the same owner/key pair is
/// already present in the chain. Because the chain lives in a [Zone], the
/// frame is automatically popped when a synchronous body returns or an
/// asynchronous body completes.
T resolveWithFrame<T>(
  Object owner,
  DependencyKey key,
  T Function() body,
) {
  final chain = currentResolutionChain;
  if (chain.any((frame) => identical(frame.owner, owner) && frame.key == key)) {
    throw BridgeCircularDependencyException(
      key.type,
      [...chain.map((frame) => frame.key.type), key.type],
    );
  }

  return runZoned(
    body,
    zoneValues: {
      _resolutionChainZoneKey: <ResolutionFrame>[
        ...chain,
        ResolutionFrame(owner: owner, key: key),
      ],
    },
  );
}

/// Async variant of [resolveWithFrame]. The returned future completes with
/// the result of [body]; the frame stays on the chain for the whole async
/// execution of [body].
Future<T> resolveWithFrameAsync<T>(
  Object owner,
  DependencyKey key,
  Future<T> Function() body,
) {
  final chain = currentResolutionChain;
  if (chain.any((frame) => identical(frame.owner, owner) && frame.key == key)) {
    return Future<T>.error(
      BridgeCircularDependencyException(
        key.type,
        [...chain.map((frame) => frame.key.type), key.type],
      ),
    );
  }

  return runZoned(
    body,
    zoneValues: {
      _resolutionChainZoneKey: <ResolutionFrame>[
        ...chain,
        ResolutionFrame(owner: owner, key: key),
      ],
    },
  );
}
