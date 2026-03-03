import 'package:fn/fn.dart';
import 'package:test/test.dart';

// ─── Shared test nodes ────────────────────────────────────────────────────────

class Increment extends Fx<int> {
  final int value;
  Increment(this.value) : super(() => value + 1);
}

class DoubleIt extends Fx<int> {
  final int value;
  DoubleIt(this.value) : super(() => value * 2);
}

// Delegates to Increment; used to test override propagation to grandchildren.
class AddOneViaIncrement extends Fx<int> {
  AddOneViaIncrement(int n) : super(() async => await Increment(n));
}

// Write/PrettyWrite pair: PrettyWrite calls Write internally to test that the
// active override is suspended during replacement execution.
class Write extends Fx<String> {
  final String msg;
  Write(this.msg) : super(() async => msg);
}

class PrettyWrite extends Fx<String> {
  PrettyWrite(String msg) : super(() async => '>>> ${await Write(msg)}');
}

// Concrete StreamFx for testing (StreamFx is abstract, must be subclassed).
class CountUp extends StreamFx<int> {
  final int count;
  CountUp(this.count)
    : super(() async* {
        for (var i = 0; i < count; i++) {
          yield i;
        }
      });
}

class ErrorStream extends StreamFx<int> {
  ErrorStream()
    : super(() async* {
        yield 1;
        throw StateError('stream error');
      });
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('Fx', () {
    test('runs synchronous body', () async {
      expect(await Fx(() => 42), 42);
    });

    test('runs asynchronous body', () async {
      expect(await Fx(() async => 'hello'), 'hello');
    });

    test('is directly awaitable as a Future', () async {
      final value = await Fx(() => 99);
      expect(value, 99);
    });

    test('propagates synchronous errors', () {
      expect(Fx<int>(() => throw StateError('boom')), throwsStateError);
    });

    test('propagates asynchronous errors', () {
      expect(
        Fx<int>(() async => throw StateError('async boom')),
        throwsStateError,
      );
    });
  });

  group('StreamFx', () {
    test('emits values in order', () async {
      expect(await CountUp(3).toList(), [0, 1, 2]);
    });

    test('each listen reruns the body independently', () async {
      var runs = 0;
      final stream = _CountingStream(() async* {
        runs++;
        yield runs;
      });
      await stream.first;
      await stream.first;
      expect(runs, 2);
    });

    test('propagates errors', () {
      expect(ErrorStream().toList(), throwsStateError);
    });
  });

  group('Override', () {
    test('replaces a node with a different implementation', () async {
      // Override is keyed on runtimeType; second type param must satisfy
      // `F extends Node<T>`. Using Object works because FutureOr<int> <: Object.
      final result = await Fx<int>(
        overrides: {Override<Increment, Object>((fx) => DoubleIt(fx.value))},
        () async => await Increment(5),
      );
      // Without override: 5+1=6; with override: 5*2=10
      expect(result, 10);
    });

    test('override is visible to transitive children', () async {
      final result = await Fx<int>(
        overrides: {Override<Increment, Object>((fx) => DoubleIt(fx.value))},
        () async => await AddOneViaIncrement(4),
      );
      // AddOneViaIncrement → Increment(4) → overridden → DoubleIt(4) = 8
      expect(result, 8);
    });

    test('replacement can call the original type without infinite recursion',
        () async {
      // PrettyWrite calls Write internally. The override (Write→PrettyWrite)
      // must be inactive when the replacement runs, or this would loop forever.
      final result = await Fx<String>(
        overrides: {Override<Write, Object>((fx) => PrettyWrite(fx.msg))},
        () async => await Write('hello'),
      );
      expect(result, '>>> hello');
    });

    test('override declared via getter on the node class', () async {
      // _AppWithOverride declares its overrides via the getter, not the ctor.
      expect(await _AppWithOverride(5), 10); // DoubleIt(5) = 10
    });

    test('inner override does not leak to subsequent sibling effects', () async {
      int? withOverride, withoutOverride;
      await Fx<void>(() async {
        withOverride = await Fx<int>(
          overrides: {Override<Increment, Object>((fx) => DoubleIt(fx.value))},
          () async => await Increment(3),
        );
        withoutOverride = await Increment(3); // should not be overridden
      });
      expect(withOverride, 6); // DoubleIt(3)
      expect(withoutOverride, 4); // Increment(3) unaffected
    });
  });

  group('Access', () {
    test('throws StateError when no value has been provided', () {
      expect(Access<String>(), throwsStateError);
    });

    test('value() constructor returns the wrapped value', () async {
      expect(await Access<String>.value('hi'), 'hi');
    });
  });

  group('WithValue', () {
    test('makes the value accessible via Access within the inner effect',
        () async {
      final result = await WithValue<String, int>((
        'hello',
        Fx(() async {
          final s = await Access<String>();
          return s.length;
        }),
      ));
      expect(result, 5);
    });

    test('different Access types are independent', () async {
      final result = await WithValue<int, String>((
        42,
        Fx(() async => 'n=${await Access<int>()}'),
      ));
      expect(result, 'n=42');
    });

    test('Access throws outside WithValue scope', () {
      expect(Access<String>(), throwsStateError);
    });
  });

  group('Bracket', () {
    test('provides resource to use and calls close', () async {
      var released = false;

      final result = await Bracket<String, int>((
        Fx(() async => 'resource'),
        Fx(() async {
          await Access<String>(); // confirms Access works in close
          released = true;
        }),
        Fx(() async {
          final s = await Access<String>();
          return s.length;
        }),
      ));

      expect(result, 8); // 'resource'.length
      expect(released, isTrue);
    });

    test('calls close even when use throws', () async {
      var released = false;

      await expectLater(
        Bracket<String, int>((
          Fx(() async => 'resource'),
          Fx(() async {
            released = true;
          }),
          Fx<int>(() => throw StateError('use failed')),
        )).asFuture(),
        throwsStateError,
      );

      expect(released, isTrue);
    });

    test('rethrows the error from use after close', () async {
      Object? caught;
      try {
        await Bracket<String, void>((
          Fx(() async => 'res'),
          Fx(() async {}),
          Fx<void>(() => throw ArgumentError('bad')),
        ));
      } on ArgumentError catch (e) {
        caught = e;
      }
      expect(caught, isA<ArgumentError>());
    });
  });

  group('Events', () {
    // Collect events emitted during the inner Fx into a synchronous list.
    Future<List<SystemEvent>> collectEvents(
      Future<void> Function() body,
    ) async {
      final events = <SystemEvent>[];
      await Fx(() async {
        Context.current.events.stream.listen(events.add);
        await body();
      });
      return events;
    }

    test('OnRun is emitted when an effect starts', () async {
      final events = await collectEvents(() async {
        await Fx(() async => 42);
      });
      expect(events.whereType<OnRun>(), isNotEmpty);
    });

    test('OnSuccess is emitted when an effect completes successfully', () async {
      final events = await collectEvents(() async {
        await Fx(() async => 42);
      });
      expect(events.whereType<OnSuccess>(), isNotEmpty);
    });

    test('OnError is emitted when an effect throws', () async {
      final events = await collectEvents(() async {
        try {
          await Fx<int>(() => throw StateError('oops'));
        } catch (_) {}
      });
      expect(events.whereType<OnError>(), isNotEmpty);
    });

    test('OnSuccess carries the returned value', () async {
      final events = await collectEvents(() async {
        await Fx(() async => 7);
      });
      final successes = events.whereType<OnSuccess>().toList();
      expect(successes.any((e) => e.arg.$2 == 7), isTrue);
    });

    test('OnError carries the thrown object', () async {
      final events = await collectEvents(() async {
        try {
          await Fx<void>(() => throw StateError('tracked'));
        } catch (_) {}
      });
      final errors = events.whereType<OnError>().toList();
      expect(errors.single.arg.$2, isA<StateError>());
    });
  });

  group('Callstack', () {
    test('contains the running node during execution', () async {
      late List<Node> stack;
      final effect = Fx(() async {
        stack = Context.current.callstack;
      });
      await effect;
      expect(stack, isNotEmpty);
      expect(stack.last, same(effect));
    });

    test('grows with nesting depth', () async {
      late List<Node> innerStack;
      await Fx(() async {
        await Fx(() async {
          innerStack = Context.current.callstack;
        });
      });
      expect(innerStack.length, greaterThanOrEqualTo(2));
    });
  });
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

// Declares overrides via the getter instead of the constructor parameter.
class _AppWithOverride extends Fx<int> {
  final int n;
  _AppWithOverride(this.n) : super(() async => await Increment(0));

  @override
  Overrides get overrides => {Override<Increment, Object>((_) => DoubleIt(n))};
}

// Concrete StreamFx that wraps an arbitrary generator for testing.
class _CountingStream extends StreamFx<int> {
  _CountingStream(Stream<int> Function() gen) : super(gen);
}
