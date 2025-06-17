import 'dart:async';

import 'package:async_effects/src/context.dart';
import 'package:async_effects/src/lazy_future_mixin.dart';
import 'package:meta/meta.dart';

sealed class AnyOverride {}

/// Replaces every node of type [F] encountered in an effect's subtree with the
/// result of [value]. The replacement receives the original node, so it can
/// forward any constructor arguments.
@optionalTypeArgs
final class Override<F extends Node<T>, T> implements AnyOverride {
  final Fx<T> Function(F) value;

  Override(this.value);

  Type get type => F;
}

typedef Overrides = Set<AnyOverride>;

typedef Callstack = List<Node>;

/// Base interface for all effect nodes. [T] is the raw output type
/// (e.g. `FutureOr<int>` for `Fx<int>`, `Stream<int>` for `StreamFx<int>`).
abstract interface class Node<T> {
  @protected
  T run();

  Overrides get overrides;
}

mixin _NodeMixin<T> implements Node<T> {
  ContextPayload get context => Context.current;

  /// Zoned body to be implemented in base classes
  T _run();

  /// Output evaluation
  T _runZoned() {
    // If a parent registered an override for this node type, delegate to it.
    // The replacement runs in a zone without the current override to prevent
    // infinite recursion when the replacement internally uses the same type.
    final overrideFn = Context.current.overrides[runtimeType];
    if (overrideFn != null) {
      // Cast `this` to dynamic so the call bypasses the static parameter type
      // check — the actual runtime type is always the correct concrete node type.
      final replacement = (overrideFn as dynamic)(this as dynamic);
      if (replacement is _NodeMixin<T> && !identical(replacement, this)) {
        final childOverrides =
            Map<Type, dynamic>.from(Context.current.overrides)
              ..remove(runtimeType);
        return Context.runZoned(
          replacement._runZoned,
          zoneValues: (
            callstack: Context.current.callstack,
            overrides: childOverrides,
            events: Context.current.events,
          ),
        );
      }
    }

    // Merge this node's declared overrides into the zone so children see them.
    // Dynamic access avoids the smart-cast covariant field check at runtime.
    final childOverrides =
        overrides.isEmpty
            ? Context.current.overrides
            : <Type, dynamic>{
              ...Context.current.overrides,
              for (final e in overrides)
                if (e is Override)
                  (e as dynamic).type as Type: (e as dynamic).value,
            };

    return Context.runZoned(
      _run,
      zoneValues: (
        callstack: [...Context.current.callstack, this],
        overrides: childOverrides,
        events: Context.current.events,
      ),
    );
  }

  @override
  String toString() => runtimeType.toString();
}

/// Marker for internal lifecycle events. System events skip the normal
/// OnRun/OnSuccess/OnError cycle to avoid infinite recursion.
sealed class SystemEvent {}

mixin NoOp implements Node<void> {
  @override
  void run() {}
}

base class _Fn<A> extends Fx<void> {
  final A arg;

  _Fn(this.arg) : super(() {});

  @override
  Overrides get overrides => const {};

  @override
  String toString() => '$runtimeType($arg)';
}

final class OnRun = _Fn<Callstack> with NoOp implements SystemEvent;

final class OnSuccess<T> = _Fn<(Callstack, T)> with NoOp implements SystemEvent;

final class OnError = _Fn<(Callstack, Object, StackTrace)>
    with NoOp
    implements SystemEvent;

abstract interface class IFx<T>
    implements Node<FutureOr<T>>, FutureConvertible<T> {}

/// A lazy async effect that implements [Future<T>].
///
/// Execution is deferred until the instance is `await`ed or [asFuture] is
/// called. Subclass to give the effect a meaningful name that [Override] can
/// target by [runtimeType].
class Fx<T>
    with _NodeMixin<FutureOr<T>>, LazyFutureMixin<T>
    implements Node<FutureOr<T>>, FutureConvertible<T> {
  final FutureOr<T> Function() _body;
  @override
  final Overrides overrides;

  const Fx(this._body, {this.overrides = const {}});

  factory Fx.pure(FutureOr<T> Function() body, {Overrides overrides}) = _Fx<T>;

  @override
  Future<T> _run() async {
    final isSystem = this is SystemEvent;
    if (this is SystemEvent) {
      Context.current.events.add(this as SystemEvent);
    }
    if (!isSystem) await OnRun(Context.current.callstack);
    try {
      final value = await run();
      if (!isSystem) await OnSuccess((Context.current.callstack, value));
      return value;
    } on Object catch (e, s) {
      if (!isSystem) await OnError((Context.current.callstack, e, s));
      rethrow;
    }
  }

  @override
  Future<T> asFuture() async => await _runZoned();

  @override
  FutureOr<T> run() => _body();
}

final class _Fx<T> extends Fx<T> {
  const _Fx(super.body, {super.overrides});
}

/// A lazy streaming effect. Each [listen] call reruns the body independently.
///
/// Subclass to name the stream so it can be targeted by [Override].
abstract class StreamFx<T> extends Stream<T>
    with _NodeMixin<Stream<T>>
    implements Node<Stream<T>> {
  final Stream<T> Function() _body;
  @override
  final Overrides overrides;

  const StreamFx(this._body, {this.overrides = const {}});

  @override
  Stream<T> _run() async* {
    try {
      await for (final value in run()) {
        yield value;
      }
    } on Object {
      rethrow;
    }
  }

  @override
  Stream<T> run() => _body();

  @override
  StreamSubscription<T> listen(
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _runZoned().listen(
    onData,
    onDone: onDone,
    onError: onError,
    cancelOnError: cancelOnError,
  );
}
