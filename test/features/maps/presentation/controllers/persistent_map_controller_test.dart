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

  group('restoration runs exactly once per surface', () {
    // Every layer redraws its geometry off a generation bump. Two owners each
    // believing they had to rebuild produced two bumps and two full restore
    // passes for a single resume — which is the defect this claim removes.
    test('no restoration is claimed before a surface exists', () {
      expect(controller.claimRestoration(), isFalse);
      expect(controller.isRestored, isFalse);
    });

    test('the first claim after attach wins, later ones do not', () {
      controller.attach(_FakeMapboxMap());

      expect(controller.claimRestoration(), isTrue);
      expect(controller.isRestored, isTrue);
      expect(
        controller.claimRestoration(),
        isFalse,
        reason: 'a repeat notification must not redraw every layer again',
      );
      expect(controller.claimRestoration(), isFalse);
    });

    test('a rebuilt surface is restorable exactly once again', () {
      controller
        ..attach(_FakeMapboxMap())
        ..recreate();

      // No surface yet on the new generation.
      expect(controller.claimRestoration(), isFalse);
      expect(controller.isRestored, isFalse);

      controller.attach(_FakeMapboxMap());
      expect(controller.claimRestoration(), isTrue);
      expect(controller.claimRestoration(), isFalse);
    });

    test('one resume yields one generation bump and one restoration', () {
      controller.attach(_FakeMapboxMap());
      controller.claimRestoration();
      final before = controller.generation;

      // The single owner rebuilds the surface on resume.
      controller
        ..recreate()
        ..attach(_FakeMapboxMap());

      expect(controller.generation, before + 1);

      var restores = 0;
      for (var i = 0; i < 5; i++) {
        if (controller.claimRestoration()) restores++;
      }
      expect(restores, 1);
    });

    test('a disposed controller never claims a restoration', () {
      final disposable = PersistentMapController()
        ..attach(_FakeMapboxMap())
        ..dispose();

      expect(disposable.claimRestoration(), isFalse);
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
