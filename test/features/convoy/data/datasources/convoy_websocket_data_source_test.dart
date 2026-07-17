import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/features/convoy/data/datasources/convoy_websocket_data_source.dart';

void main() {
  group('disconnect recovery classification', () {
    test('reconnects after a server heartbeat timeout', () {
      expect(
        shouldReconnectAfterDisconnect(
          'io server disconnect',
          heartbeatTimedOut: true,
        ),
        isTrue,
      );
    });

    test('does not reconnect after a logout server disconnect', () {
      expect(
        shouldReconnectAfterDisconnect(
          'io server disconnect',
          heartbeatTimedOut: false,
        ),
        isFalse,
      );
    });

    test('reconnects after a transport failure', () {
      expect(
        shouldReconnectAfterDisconnect(
          'transport close',
          heartbeatTimedOut: false,
        ),
        isTrue,
      );
    });
  });
}
