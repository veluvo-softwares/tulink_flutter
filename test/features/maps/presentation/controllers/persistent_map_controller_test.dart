import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:tulink_flutter/features/maps/presentation/controllers/persistent_map_controller.dart';

/// The shared surface handle. Every layer in the app draws through this, so its
/// generation contract is what stops a late async callback from painting onto a
/// surface the user is no longer looking at.
void main() {
  late PersistentMapController controller;
  late int notifications;

  setUp(() {
    controller = PersistentMapController();
    notifications = 0;
    controller.addListener(() => notifications++);
  });

  tearDown(() => controller.dispose());

  group('surface attachment', () {
    test('starts with no surface', () {
      expect(controller.map, isNull);
      expect(controller.isReady, isFalse);
      expect(controller.generation, 0);
    });

    test('attaching publishes the surface to listeners', () {
      final map = _FakeMapboxMap();

      controller.attach(map);

      expect(controller.isReady, isTrue);
      expect(identical(controller.map, map), isTrue);
      expect(notifications, 1);
    });

    test('attaching does not bump the generation', () {
      // Only a genuine surface *replacement* invalidates in-flight work.
      // Treating the first attach as a replacement would make every layer
      // discard the work it started while waiting for that very surface.
      controller.attach(_FakeMapboxMap());

      expect(controller.generation, 0);
    });
  });

  group('surface recreation', () {
    test('drops the surface and bumps the generation', () {
      controller
        ..attach(_FakeMapboxMap())
        ..recreate();

      expect(
        controller.map,
        isNull,
        reason: 'the old handle points at a surface that is being torn down',
      );
      expect(controller.generation, 1);
    });

    test('each rebuild yields a distinct generation', () {
      controller
        ..recreate()
        ..recreate()
        ..recreate();

      expect(controller.generation, 3);
    });

    test('a reattached surface is usable again', () {
      final replacement = _FakeMapboxMap();
      controller
        ..attach(_FakeMapboxMap())
        ..recreate()
        ..attach(replacement);

      expect(identical(controller.map, replacement), isTrue);
      expect(controller.generation, 1);
    });
  });

  group('user pan reporting', () {
    test('a reported pan increments the tick', () {
      expect(controller.userPanTick, 0);

      controller.reportUserPan();

      expect(controller.userPanTick, 1);
      expect(notifications, 1);
    });

    test('recreating the surface does not fabricate a pan', () {
      // A layer that mistook a surface rebuild for a hand pan would silently
      // disable camera-follow after every background/foreground cycle.
      controller
        ..attach(_FakeMapboxMap())
        ..recreate();

      expect(controller.userPanTick, 0);
    });
  });

  group('disposal', () {
    test('ignores late calls and releases the surface', () {
      final disposable = PersistentMapController()
        ..attach(_FakeMapboxMap())
        ..dispose();

      // A platform callback can outlive the widget that owned the controller;
      // it must not resurrect a handle to a dead surface.
      expect(
        () => disposable
          ..attach(_FakeMapboxMap())
          ..recreate()
          ..reportUserPan(),
        returnsNormally,
      );
      expect(disposable.map, isNull);
      expect(disposable.generation, 0);
      expect(disposable.userPanTick, 0);
    });
  });
}

/// The controller only ever stores and republishes the handle, so an empty
/// stand-in is enough — and keeps these tests off Mapbox platform channels.
class _FakeMapboxMap implements MapboxMap {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
