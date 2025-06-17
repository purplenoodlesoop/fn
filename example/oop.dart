import 'dart:io';

class Console {
  const Console();

  Future<String> read() async {
    return stdin.readLineSync()!;
  }

  Future<void> write(Object message) async {
    stdout.writeln(message);
  }
}

class App {
  final Console console;

  App(this.console);

  Future<void> main() async {
    await console.write('What is your favorite number?');
    final number = await console.read();
    await console.write('It would ${int.parse(number) * 2} if doubled');
  }
}

Future<void> main() async {
  await App(Console()).main();
}
