import 'dart:async';

import 'package:async_effects/src/core.dart';

/// Retrieves a value of type [T] from the zone context.
///
/// Throws [StateError] when awaited outside a [WithValue] scope.
/// Use [Access.value] to create a pre-filled instance (useful in overrides).
final class Access<T> extends Fx<T> {
  Access.value(T arg) : super(() => arg);

  Access() : super(() => throw StateError('Value not initialized'));
}

/// Runs [arg.$2] in a zone where `Access<A>()` returns [arg.$1].
class WithValue<A, T> extends Fx<T> {
  WithValue((A, Fx<T>) arg)
    : super(
        overrides: {
          Override<Access<A>, FutureOr<A>>((_) => Access<A>.value(arg.$1)),
        },
        () async => await arg.$2,
      );
}

/// Acquires a resource with [arg.$1], provides it via [Access] to [arg.$3],
/// and guarantees [arg.$2] (release) runs even if [arg.$3] (use) throws.
class Bracket<A, B> extends Fx<B> {
  Bracket((Fx<A>, Fx<void>, Fx<B>) arg)
    : super(() async {
        final (create, close, use) = arg;
        final value = await create;
        try {
          return await WithValue<A, B>((value, use));
        } finally {
          await WithValue<A, void>((value, close));
        }
      });
}
