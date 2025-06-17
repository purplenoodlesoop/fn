import 'dart:async' as async;

import 'package:async_effects/src/core.dart';

// Keys are the concrete node Type, matching Override<F,T>.type.
typedef ContextPayload = ({
  Callstack callstack,
  Map<Type, dynamic> overrides,
  async.StreamController<SystemEvent> events,
});

extension type const Context(ContextPayload payload) {
  static ContextPayload get current =>
      ((async.Zone.current[Context] as Context?) ??
              Context((
                callstack: const [],
                overrides: const <Type, dynamic>{},
                events: async.StreamController.broadcast(),
              )))
          .payload;

  static T runZoned<T>(
    T Function() body, {
    required ContextPayload zoneValues,
  }) => async.runZoned(body, zoneValues: {Context: Context(zoneValues)});
}
