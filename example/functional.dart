import 'dart:async';

import 'package:fn/fn.dart';

class DoPrint extends Fx<void> {
  final Object? arg;
  DoPrint(this.arg) : super(() => print(arg));
}

class PrettyPrint extends Fx<void> {
  final Object? arg;
  PrettyPrint(this.arg) : super(() async => await DoPrint('>>> $arg'));
}

final printEverything = Fx<void>(() async {
  await DoPrint('Hello');
  await DoPrint('World');
});

final app = Fx<void>(
  overrides: {Override<DoPrint, FutureOr<void>>((fx) => PrettyPrint(fx.arg))},
  () async {
    await printEverything;
  },
);

void main() => app.asFuture();
