import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldens/goldens.dart';

final GoldenConfiguration testPhoneUnboundHeight = GoldenConfiguration(
  name: 'phone',
  pixelRatio: 3.0,
  constraints: BoxConstraints.tightFor(width: 375),
);

final GoldenConfiguration testTabletUnboundHeight = GoldenConfiguration(
  name: 'tablet',
  pixelRatio: 3.0,
  constraints: BoxConstraints.tightFor(width: 843),
);

void main() {
  Goldens.configure(GoldensConfiguration(
    fileNameFactory: (String name, GoldenConfiguration config) {
      return 'goldens/${name}_${config.name}.png';
    }
  ));

  testWidgets('shrinkSurfaceWithinConstraints shrinks to a size which is inside the constraints',
      (WidgetTester tester) async {
    final BoxConstraints constraints = BoxConstraints(
      minWidth: 100,
      minHeight: 100,
      maxWidth: 200,
      maxHeight: 200,
    );

    await tester.pumpWidget(Center(
      child: Container(
        height: 150,
        width: 150,
      ),
    ));

    await tester.shrinkSurfaceWithinConstraints(find.byType(Container), constraints);

    expect(tester.binding.renderView.size.width, 150);
    expect(tester.binding.renderView.size.height, 150);
  });

  testWidgets('shrinkSurfaceWithinConstraints only shrinks to the minimum allowed by the given constraints',
      (WidgetTester tester) async {
    final BoxConstraints constraints = BoxConstraints(
      minWidth: 100,
      minHeight: 100,
      maxWidth: 200,
      maxHeight: 200,
    );

    await tester.pumpWidget(Center(
      child: Container(
        height: 50,
        width: 50,
      ),
    ));

    await tester.shrinkSurfaceWithinConstraints(find.byType(Container), constraints);

    expect(tester.binding.renderView.size.width, 100);
    expect(tester.binding.renderView.size.height, 100);
  });

  testWidgets('expandSurfaceWithinConstraints expands a single vertical finite ListView', (WidgetTester tester) async {
    final BoxConstraints constraints = BoxConstraints.tightFor(
      width: 100,
    );

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: ListView.builder(
        itemBuilder: (BuildContext context, int index) {
          return Container(height: 200);
        },
        itemCount: 10,
      ),
    ));

    await tester.expandSurfaceWithinConstraints(_getFiniteScrollableStates(), constraints);

    expect(tester.binding.renderView.size.width, 100);
    expect(tester.binding.renderView.size.height, 2000);
  });

  testWidgets('expandSurfaceWithinConstraints expands a infinite vertical ListView to biggest constraints',
      (WidgetTester tester) async {
    final BoxConstraints constraints = BoxConstraints(
      minWidth: 100,
      maxWidth: 100,
      minHeight: 100,
      maxHeight: 2000,
    );

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: ListView.builder(
        itemBuilder: (BuildContext context, int index) {
          return Container(height: 200);
        },
      ),
    ));

    await tester.expandSurfaceWithinConstraints(_getInfiniteScrollableStates(), constraints);

    expect(tester.binding.renderView.size.width, 100);
    expect(tester.binding.renderView.size.height, 2000);
  });

  testWidgets('GoldenInputMatcher shrink works for centered fixed size container', (WidgetTester tester) async {
    await tester.pumpGoldenWidget(Center(
      child: Container(
        height: 100,
        color: Colors.green,
      ),
    ));

    final GoldenInputMatcher matcher = GoldenInputMatcher('shrink');
    await matcher.matchAsync(tester.getGoldens(
      configurations: <GoldenConfiguration>[testPhoneUnboundHeight, testTabletUnboundHeight],
      shrink: find.byType(Container),
    ));
  });

  testWidgets('GoldenInputMatcher expand works for finite scroll list', (WidgetTester tester) async {
    await tester.pumpGoldenWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: ListView.builder(
        itemBuilder: (BuildContext context, int index) {
          return Container(
            height: 200,
            color: Colors.blue.withBlue((index / 10 * 255).toInt()),
          );
        },
        itemCount: 10,
      ),
    ));

    final GoldenInputMatcher matcher = GoldenInputMatcher('expand');
    await matcher.matchAsync(tester.getGoldens(
        configurations: <GoldenConfiguration>[testPhoneUnboundHeight, testTabletUnboundHeight], expand: true));
  });
}

List<ScrollableState> _getFiniteScrollableStates() {
  return find
      .byType(Scrollable)
      .evaluate()
      .map<ScrollableState>((Element element) {
        return (element as StatefulElement).state as ScrollableState;
      })
      .where((ScrollableState scrollableState) => scrollableState.position.extentAfter.isFinite)
      .toList(growable: false);
}

List<ScrollableState> _getInfiniteScrollableStates() {
  return find
      .byType(Scrollable)
      .evaluate()
      .map<ScrollableState>((Element element) {
        return (element as StatefulElement).state as ScrollableState;
      })
      .where((ScrollableState scrollableState) => scrollableState.position.extentAfter.isInfinite)
      .toList(growable: false);
}
