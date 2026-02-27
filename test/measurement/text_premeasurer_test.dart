import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_reader/flutter_reader.dart';

void main() {
  group('TextPremeasurer', () {
    late TextPremeasurer premeasurer;

    setUp(() {
      premeasurer = TextPremeasurer();
    });

    test('measureText returns positive height for non-empty text', () {
      final result = premeasurer.measureText(
        text: 'Hello, world!',
        style: const TextStyle(fontSize: 16),
        maxWidth: 200,
      );

      expect(result.height, greaterThan(0));
      expect(result.confidence, 0.9);
    });

    test('measureText includes padding', () {
      const padding = EdgeInsets.symmetric(horizontal: 16, vertical: 8);

      final withoutPadding = premeasurer.measureText(
        text: 'Hello',
        style: const TextStyle(fontSize: 16),
        maxWidth: 200,
      );

      final withPadding = premeasurer.measureText(
        text: 'Hello',
        style: const TextStyle(fontSize: 16),
        maxWidth: 200,
        padding: padding,
      );

      expect(withPadding.height, greaterThan(withoutPadding.height));
      expect(
        withPadding.height - withoutPadding.height,
        closeTo(padding.vertical, 1.0),
      );
    });

    test('longer text produces taller height', () {
      final short = premeasurer.measureText(
        text: 'Hi',
        style: const TextStyle(fontSize: 16),
        maxWidth: 100,
      );

      final long = premeasurer.measureText(
        text: 'This is a much longer piece of text that should wrap to '
            'multiple lines when laid out in a narrow column.',
        style: const TextStyle(fontSize: 16),
        maxWidth: 100,
      );

      expect(long.height, greaterThan(short.height));
    });

    test('narrower width wraps more and produces taller height', () {
      const text = 'This is a sentence that will wrap differently at '
          'different widths.';

      final wide = premeasurer.measureText(
        text: text,
        style: const TextStyle(fontSize: 16),
        maxWidth: 400,
      );

      final narrow = premeasurer.measureText(
        text: text,
        style: const TextStyle(fontSize: 16),
        maxWidth: 100,
      );

      expect(narrow.height, greaterThan(wide.height));
    });

    test('zero/negative available width returns padding only', () {
      final result = premeasurer.measureText(
        text: 'Hello',
        style: const TextStyle(fontSize: 16),
        maxWidth: 10,
        padding: const EdgeInsets.all(20), // 40 horizontal > 10 maxWidth
      );

      expect(result.height, 40.0); // vertical padding only
      expect(result.confidence, 0.5);
    });

    test('measureTextSpan works with rich text', () {
      final result = premeasurer.measureTextSpan(
        textSpan: const TextSpan(
          children: [
            TextSpan(
              text: 'Bold ',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            TextSpan(
              text: 'and normal',
              style: TextStyle(fontSize: 16),
            ),
          ],
        ),
        maxWidth: 200,
      );

      expect(result.height, greaterThan(0));
      expect(result.confidence, 0.85);
    });

    test('createEstimator returns compatible function', () {
      final estimator = premeasurer.createEstimator(
        textExtractor: (data) => data['text'] as String,
        style: const TextStyle(fontSize: 16),
        padding: const EdgeInsets.all(8),
      );

      final result = estimator({'text': 'Hello, world!'}, 200);
      expect(result.height, greaterThan(0));
      expect(result.confidence, 0.9);
    });

    test('createRichEstimator returns compatible function', () {
      final estimator = premeasurer.createRichEstimator(
        spanBuilder: (data) => TextSpan(
          text: data['text'] as String,
          style: const TextStyle(fontSize: 16),
        ),
      );

      final result = estimator({'text': 'Hello'}, 200);
      expect(result.height, greaterThan(0));
      expect(result.confidence, 0.85);
    });
  });
}
