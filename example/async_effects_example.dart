// ignore_for_file: await_only_futures

import 'dart:async';
import 'dart:io';

import 'package:async_effects/async_effects.dart';

class Console {
  void write(Object message) {
    stdout.write(message);
  }

  String read() => stdin.readLineSync()!;

  Future<void> close() async {}
}

class CreateConsole extends Fx<Console> {
  CreateConsole() : super(Console.new);
}

class CloseConsole extends Fx<void> {
  CloseConsole()
    : super(() async {
        final console = await Access<Console>();
        await console.close();
      });
}

class WriteConsole extends Fx<void> {
  WriteConsole(String arg)
    : super(() async {
        final console = await Access<Console>();
        console
          ..write('<< $arg')
          ..write('\n');
      });
}

class ReadConsole extends Fx<String> {
  ReadConsole()
    : super(() => Access<Console>().then((console) => console.read()));
}

class PromptedReadConsole extends Fx<String> {
  PromptedReadConsole(({String prompt}) arg)
    : super(() async {
        await WriteConsole('${arg.prompt} ');

        return await ReadConsole();
      });
}

class RequestFavoriteNumber extends Fx<int> {
  RequestFavoriteNumber()
    : super(() async {
        await WriteConsole('What is your favorite number?');
        final input = await ReadConsole();
        final number = int.parse(input);
        await WriteConsole('Your favorite number is $number');

        return number;
      });
}

class ThrowIntentionally extends Fx<void> {
  ThrowIntentionally()
    : super(() {
        throw Exception(
          'This is an intentional exception for testing purposes.',
        );
      });
}

class UserInteraction extends StreamFx<int> {
  UserInteraction()
    : super(() async* {
        final interact = RequestFavoriteNumber();
        await WriteConsole('First interaction');
        yield await interact;
        await WriteConsole('Second interaction');
        yield await interact;
        try {
          await ThrowIntentionally();
        } on Object catch (_) {
          await WriteConsole('Caught an error from ThrowIntentionally');
        }
      });
}

class PerformUserInteraction extends Fx<void> {
  PerformUserInteraction(({String prompt}) arg)
    : super(
        overrides: {
          Override<ReadConsole, Object>(
            (_) => PromptedReadConsole((prompt: arg.prompt)),
          ),
        },
        () async {
          final numbers = await UserInteraction().toList();
          await WriteConsole('You entered: $numbers');
        },
      );
}

class App extends Fx<void> {
  App()
    : super(() async {
        Context.current.events.stream.listen(print);
        await Bracket((
          CreateConsole(),
          CloseConsole(),
          PerformUserInteraction((prompt: '>>')),
        ));
      });
}

void main() => App().asFuture();
