import 'dart:async';

abstract interface class FutureConvertible<T> implements Future<T> {
  Future<T> asFuture();
}

mixin LazyFutureMixin<T> implements FutureConvertible<T> {
  @override
  Stream<T> asStream() => asFuture().asStream();

  @override
  Future<R> then<R>(
    FutureOr<R> Function(T value) onValue, {
    Function? onError,
  }) => asFuture().then(onValue, onError: onError);

  @override
  Future<T> catchError(Function onError, {bool Function(Object error)? test}) =>
      asFuture().catchError(onError, test: test);

  @override
  Future<T> timeout(Duration timeLimit, {FutureOr<T> Function()? onTimeout}) =>
      asFuture().timeout(timeLimit, onTimeout: onTimeout);

  @override
  Future<T> whenComplete(FutureOr<void> Function() action) =>
      asFuture().whenComplete(action);
}
