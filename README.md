# async_effects

A lightweight Dart library for composable, testable asynchronous effects.

Effects are **lazy**, **named**, and **swappable**: any node in the call tree can be transparently replaced at runtime, making dependency injection and testing trivial without mocks or service locators.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Core Concepts](#core-concepts)
  - [Fx — async effect](#fx--async-effect)
  - [StreamFx — streaming effect](#streamfx--streaming-effect)
  - [Override — dependency injection](#override--dependency-injection)
  - [Access / WithValue — contextual values](#access--withvalue--contextual-values)
  - [Bracket — resource lifecycle](#bracket--resource-lifecycle)
- [Lifecycle Events](#lifecycle-events)
- [API Reference](#api-reference)

---

## Overview

Traditional DI requires passing dependencies explicitly or through a service locator. `async_effects` instead lets you **name** your effects as classes and **override** any of them in a parent effect — no parameter threading needed.

```dart
class FetchUser extends Fx<User> {
  FetchUser(int id) : super(() => http.get('/users/$id').then(User.fromJson));
}

// In tests — replace the real HTTP call with a stub:
final testApp = Fx<void>(
  overrides: {Override<FetchUser, Object>((_) => Fx(() async => User.stub()))},
  () async {
    final user = await FetchUser(42);
    print(user.name);
  },
);
```

---

## Quick Start

```yaml
dependencies:
  async_effects: ^1.0.0
```

```dart
import 'package:async_effects/async_effects.dart';

void main() async {
  await Fx(() async {
    print('hello, effects!');
  });
}
```

---

## Core Concepts

### Fx — async effect

`Fx<T>` is a lazy, named unit of async work. It is not executed until awaited.

```dart
class SaveUser extends Fx<void> {
  SaveUser(User user) : super(() => db.save(user));
}

await SaveUser(user); // executes here
```

`Fx<T>` implements `Future<T>`, so it can be `await`ed directly.

---

### StreamFx — streaming effect

`StreamFx<T>` is the streaming counterpart. Subclass it and provide a generator body.

```dart
class UserStream extends StreamFx<User> {
  UserStream() : super(() async* {
    yield await FetchUser(1);
    yield await FetchUser(2);
  });
}

final users = await UserStream().toList();
```

Each `listen` call reruns the body independently.

---

### Override — dependency injection

Declare `Override<NodeType, T>` in a parent effect's `overrides` set. Any instance of `NodeType` encountered in the subtree is transparently replaced.

```dart
class Write extends Fx<void> {
  final String msg;
  Write(this.msg) : super(() => stdout.writeln(msg));
}

class PrettyWrite extends Fx<void> {
  PrettyWrite(String msg) : super(() => Write('>>> $msg'));
}

// PrettyWrite calls Write internally; the override is suspended for that call
// so there is no infinite recursion.
final app = Fx<void>(
  overrides: {Override<Write, Object>((fx) => PrettyWrite(fx.msg))},
  () async {
    await Write('hello'); // prints ">>> hello"
  },
);
```

Overrides are **zone-scoped**: they apply only within the declaring effect's subtree and do not leak to siblings or ancestors.

Overrides can also be declared via the `overrides` getter:

```dart
class App extends Fx<void> {
  App() : super(() async { ... });

  @override
  Overrides get overrides => {
    Override<Write, Object>((fx) => PrettyWrite(fx.msg)),
  };
}
```

---

### Access / WithValue — contextual values

`Access<T>` retrieves a value of type `T` that was placed in the zone context by `WithValue`. This lets effects depend on a value without receiving it as a constructor argument.

```dart
class ReadDb extends Fx<Database> {
  ReadDb() : super(() => Access<Database>());
}

class QueryUsers extends Fx<List<User>> {
  QueryUsers() : super(() async {
    final db = await ReadDb();
    return db.query('SELECT * FROM users');
  });
}

// Provide the database once at the top level:
final result = await WithValue<Database, List<User>>((
  Database.open(),
  QueryUsers(),
));
```

`Bracket` (below) uses `WithValue` internally to provide acquired resources.

---

### Bracket — resource lifecycle

`Bracket` acquires a resource, makes it available via `Access<A>` to the `use` effect, and guarantees `close` runs even if `use` throws.

```dart
await Bracket<Connection, void>((
  Fx(() => Connection.open()),   // acquire
  Fx(() async {                  // release — always called
    final conn = await Access<Connection>();
    await conn.close();
  }),
  Fx(() async {                  // use
    final conn = await Access<Connection>();
    await conn.execute('INSERT ...');
  }),
));
```

---

## Lifecycle Events

Every non-system `Fx` emits three events on `Context.current.events`:

| Event | When | Payload |
|---|---|---|
| `OnRun` | Effect starts | current callstack |
| `OnSuccess<T>` | Effect completes | `(callstack, returnValue)` |
| `OnError` | Effect throws | `(callstack, error, stackTrace)` |

Listen from within any effect:

```dart
final app = Fx<void>(() async {
  Context.current.events.stream.listen((event) {
    if (event is OnError) log.error(event.arg.$2);
  });

  await runMyApp();
});
```

`Context.current.callstack` is also available inside any running effect to inspect the current execution path.

---

## API Reference

| Symbol | Description |
|---|---|
| `Fx<T>` | Lazy async effect; implements `Future<T>` |
| `StreamFx<T>` | Abstract lazy streaming effect; extends `Stream<T>` |
| `Override<F, T>` | Replaces all `F` nodes in the subtree with a computed alternative |
| `Access<T>` | Retrieves a `T` value from zone context (throws if absent) |
| `WithValue<A, T>` | Provides a value of type `A` for `Access<A>` within an inner effect |
| `Bracket<A, B>` | Acquire / use / release pattern with guaranteed cleanup |
| `Context` | Zone-based context; exposes `callstack`, `overrides`, and `events` |
| `OnRun` | Event emitted when an effect begins executing |
| `OnSuccess<T>` | Event emitted when an effect completes successfully |
| `OnError` | Event emitted when an effect throws |
