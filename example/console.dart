import 'dart:io';

import 'package:fn/fn.dart';

class ReadNumber extends Fx<int> {
  ReadNumber() : super(() => int.parse(stdin.readLineSync()!));
}

class RequestNumbers extends StreamFx<int> {
  RequestNumbers()
    : super(() async* {
        Write('What is your favorite number?');
        yield await ReadNumber();
        Write('What is your second favorite number?');
        yield await ReadNumber();
      });
}

class PrettyWrite extends Fx<void> {
  PrettyWrite(Object? arg) : super(() => Write('>>> $arg'));
}

class Write extends Fx<void> {
  final Object? arg;

  Write(this.arg) : super(() => stdout.writeln(arg));
}

class App extends Fx<void> {
  App()
    : super(() async {
        final numbers = await RequestNumbers().toList();
        Write('Your numbers are $numbers');
      });

  @override
  Overrides get overrides => {
    Override<Write, Object?>((fx) => PrettyWrite(fx.arg)),
  };
}

Future<void> main() async {
  await App();
}
