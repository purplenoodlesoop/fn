## 1.0.0

- Initial release.
- `Fx<T>` — lazy async effect implementing `Future<T>`.
- `StreamFx<T>` — lazy streaming effect extending `Stream<T>`.
- `Override<F, T>` — zone-scoped dependency injection: transparently replaces any effect node in the subtree.
- `Access<T>` / `WithValue<A, T>` — contextual value passing without threading parameters.
- `Bracket<A, B>` — acquire / use / release pattern with guaranteed cleanup.
- `Context` — zone-based context exposing `callstack`, `overrides`, and `events`.
- Lifecycle events: `OnRun`, `OnSuccess<T>`, `OnError`.
