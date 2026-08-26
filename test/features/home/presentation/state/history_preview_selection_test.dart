import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/features/home/presentation/state/history_preview_selection.dart';

void main() {
  group('resolveHistoryPreviewId', () {
    test('defaults to the first journey when nothing is selected', () {
      expect(
        resolveHistoryPreviewId(
          availableJourneyIds: const ['newest', 'older'],
          selectedJourneyId: null,
        ),
        'newest',
      );
    });

    test('preserves an explicit non-first selection across rebuilds', () {
      expect(
        resolveHistoryPreviewId(
          availableJourneyIds: const ['newest', 'older', 'oldest'],
          selectedJourneyId: 'older',
        ),
        'older',
      );
    });

    test('falls back when the selected journey disappeared on refresh', () {
      expect(
        resolveHistoryPreviewId(
          availableJourneyIds: const ['newest', 'older'],
          selectedJourneyId: 'deleted',
        ),
        'newest',
      );
    });

    test('clears selection when history is empty', () {
      expect(
        resolveHistoryPreviewId(
          availableJourneyIds: const [],
          selectedJourneyId: 'deleted',
        ),
        isNull,
      );
    });
  });

  group('resolveHistoryPreviewErrorId', () {
    test('shows retry for the current selection when route loading fails', () {
      expect(
        resolveHistoryPreviewErrorId(
          attemptedJourneyId: 'older',
          selectedJourneyId: 'older',
          routeRendered: false,
        ),
        'older',
      );
    });

    test('ignores a failed request superseded by another selection', () {
      expect(
        resolveHistoryPreviewErrorId(
          attemptedJourneyId: 'older',
          selectedJourneyId: 'newest',
          routeRendered: false,
        ),
        isNull,
      );
    });

    test('does not show retry after a route renders', () {
      expect(
        resolveHistoryPreviewErrorId(
          attemptedJourneyId: 'older',
          selectedJourneyId: 'older',
          routeRendered: true,
        ),
        isNull,
      );
    });
  });
}
