import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:test_api/src/frontend/async_matcher.dart';

typedef FileNameFactory = String Function(String name, GoldenConfiguration configuration);
typedef AssetPrimer = Future<void> Function(WidgetTester tester);

class Goldens {
  static GoldensConfiguration _configuration;
  static GoldensConfiguration get configuration {
    if (_configuration == null) {
      throw Exception('Please first configure goldens using Goldens.configure before calling this.');
    }

    return _configuration;
  }

  static void configure(GoldensConfiguration configuration) {
    _configuration = configuration;

    if (configuration.baseDir != null) {
      goldenFileComparator = _BaseDirComparator(configuration.baseDir);
    }
  }
}

class _BaseDirComparator extends GoldenFileComparator with LocalComparisonOutput {
  _BaseDirComparator(this.basedir);

  final Uri basedir;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final File goldenFile = _getGoldenFile(golden);
    if (!goldenFile.existsSync()) {
      throw TestFailure('Could not be compared against non-existent file: "$golden"');
    }
    final List<int> goldenBytes = await goldenFile.readAsBytes();
    final ComparisonResult result = await GoldenFileComparator.compareLists(
      imageBytes,
      goldenBytes,
    );

    if (!result.passed) {
      await generateFailureOutput(result, golden, basedir);
    }
    return result.passed;
  }

  @override
  Future<void> update(Uri golden, Uint8List imageBytes) async {
    final File goldenFile = _getGoldenFile(golden);
    await goldenFile.parent.create(recursive: true);
    await goldenFile.writeAsBytes(imageBytes, flush: true);
  }

  File _getGoldenFile(Uri golden) {
    return File(join(fromUri(basedir), fromUri(golden.path)));
  }
}

@immutable
class GoldensConfiguration {
  GoldensConfiguration({
    this.baseDir,
    this.fileNameFactory,
    this.primeAssets,
  });

  final Uri baseDir;
  final FileNameFactory fileNameFactory;
  final AssetPrimer primeAssets;
}

/// TestAssetBundle is required in order to avoid issues with large assets
///
/// ref: https://medium.com/@sardox/flutter-test-and-randomly-missing-assets-in-goldens-ea959cdd336a
///
class TestAssetBundle extends CachingAssetBundle {
  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    //overriding this method to avoid limit of 10KB per asset
    final ByteData data = await load(key);
    if (data == null) {
      throw FlutterError('Unable to load asset, data is null: $key');
    }
    return utf8.decode(data.buffer.asUint8List());
  }

  @override
  Future<ByteData> load(String key) async => rootBundle.load(key);
}

extension GoldenWidgetTester on WidgetTester {
  /// Pumps the given widget wrapped in a repaint boundary and a [TestAssetBundle].
  Future<void> pumpGoldenWidget(Widget widget) async {
    await binding.setSurfaceSize(Size(1000, 1000));
    return await pumpWidget(DefaultAssetBundle(
      bundle: TestAssetBundle(),
      child: RepaintBoundary(
        child: widget,
      ),
    ));
  }

  Future<void> setSurfaceAndPump(Size size) async {
    await binding.setSurfaceSize(size);
    await pump();
  }

  /// Expands the testing surface to contain all the [scrollables].
  ///
  /// The function starts with the smallest size which is accepted by the [constraints], then tries to expand
  /// to a size where all finite scrollables are fully extended and then sets the surface to a size that is
  /// accepted by the given [constraints].
  Future<void> expandSurfaceWithinConstraints(List<ScrollableState> scrollables, BoxConstraints constraints) async {
    final double startWidth = constraints.smallest.width == 0 ? 100 : constraints.smallest.width;
    final double startHeight = constraints.smallest.height == 0 ? 100 : constraints.smallest.height;

    await setSurfaceAndPump(Size(startWidth, startHeight));

    double expandWidthBy = 0.0;
    double expandHeightBy = 0.0;

    for (ScrollableState state in scrollables) {
      if (state.position.axis == Axis.vertical) {
        expandHeightBy += state.position.extentAfter;
      } else if (state.position.axis == Axis.horizontal) {
        expandWidthBy += state.position.extentAfter;
      }
    }

    final Size adjustedSize = Size(startWidth + expandWidthBy, startHeight + expandHeightBy);
    await setSurfaceAndPump(constraints.constrain(adjustedSize));
  }

  /// Shrinks the testing surface as near as possible to the size of the render box while being
  /// inside the given constraints.
  Future<void> shrinkSurfaceWithinConstraints(Finder finder, BoxConstraints constraints) async {
    final RenderBox renderObject = this.renderObject(finder) as RenderBox;
    final Size newSurfaceSize = constraints.constrain(renderObject.size);

    await setSurfaceAndPump(newSurfaceSize);
  }

  /// Creates a list of actual [GoldenMatchInput]s from a list of [GoldenConfiguration]s.
  List<GoldenMatchInput> getGoldens({
    @required List<GoldenConfiguration> configurations,
    bool expand,
    List<ScrollableState> scrollables,
    Finder shrink,
    Finder finder,
  }) {
    assert(shrink == null || expand != true, 'Shrinking and expanding at the same time makes to sense');

    return configurations
        .map<GoldenMatchInput>((GoldenConfiguration config) => GoldenMatchInput(
              tester: this,
              configuration: config,
              expand: expand,
              scrollables: scrollables,
              shrink: shrink,
              finder: finder,
            ))
        .toList(growable: false);
  }
}

enum Orientation { portrait, landscape }

/// Describes the configuration for a single golden test.
///
/// The configuration includes [constraints] in which must be respected by the output file. In addition
/// to this the configuration includes device specific settings like the current [locale], the device's
/// [pixelRation] and the currently set [textScaleFactor].
class GoldenConfiguration {
  GoldenConfiguration({
    this.name,
    this.constraints,
    this.pixelRatio,
    this.textScaleFactor,
    this.locale,
    this.orientation,
  });

  final String name;

  /// The constraints which must be respected by the output file.
  ///
  /// The size of the output file is guaranteed to be in this constraints.
  /// If you specify [expand] and have any [Scrollable]s that are infinite, this constraints must be
  /// bounded and cannot be unconstrained.
  final BoxConstraints constraints;

  // TODO document the following properties
  final double pixelRatio;
  final double textScaleFactor;
  final Locale locale;
  final Orientation orientation;

  GoldenConfiguration looseHeight({double minHeight, double maxHeight}) {
    return copyWith(
      constraints: constraints.copyWith(minHeight: minHeight ?? 0, maxHeight: maxHeight ?? double.infinity),
    );
  }

  GoldenConfiguration looseWidth({double minWidth, double minHeight}) {
    return copyWith(
      constraints: constraints.copyWith(minWidth: minWidth ?? 0, minHeight: minHeight ?? double.infinity),
    );
  }

  GoldenConfiguration copyWith({
    String name,
    BoxConstraints constraints,
    double pixelRatio,
    double textScaleFactor,
    Locale locale,
    Orientation orientation,
  }) {
    return GoldenConfiguration(
      name: name ?? this.name,
      constraints: constraints ?? this.constraints,
      pixelRatio: pixelRatio ?? this.pixelRatio,
      textScaleFactor: textScaleFactor ?? this.textScaleFactor,
      locale: locale ?? this.locale,
      orientation: orientation ?? this.orientation,
    );
  }
}

class GoldenDevice extends GoldenConfiguration {
  GoldenDevice({
    String name,
    BoxConstraints constraints,
    double pixelRatio,
    double textScaleFactor,
    Locale locale,
    this.orientation,
  }) : super(
          name: name,
          constraints: constraints,
          pixelRatio: pixelRatio,
          textScaleFactor: textScaleFactor,
          locale: locale,
        );

  final Orientation orientation;

  GoldenDevice portrait() {
    assert(constraints.isTight);

    final double width = constraints.smallest.shortestSide;
    final double height = constraints.smallest.longestSide;

    return copyWith(constraints: BoxConstraints.tight(Size(width, height)), orientation: Orientation.portrait);
  }

  GoldenDevice landscape() {
    assert(constraints.isTight);

    final double width = constraints.smallest.longestSide;
    final double height = constraints.smallest.shortestSide;

    return copyWith(constraints: BoxConstraints.tight(Size(width, height)), orientation: Orientation.landscape);
  }

  GoldenConfiguration copyWith({
    String name,
    BoxConstraints constraints,
    double pixelRatio,
    double textScaleFactor,
    Locale locale,
    Orientation orientation,
  }) {
    return GoldenDevice(
      name: name ?? this.name,
      constraints: constraints ?? this.constraints,
      pixelRatio: pixelRatio ?? this.pixelRatio,
      textScaleFactor: textScaleFactor ?? this.textScaleFactor,
      locale: locale ?? this.locale,
      orientation: orientation ?? this.orientation,
    );
  }
}

/// A input which can be passed to [matchGoldenFiles].
class GoldenMatchInput {
  GoldenMatchInput({
    this.tester,
    this.configuration,
    this.expand,
    this.scrollables,
    this.shrink,
    this.finder,
  });

  /// The widget tester that spit out this object.
  final WidgetTester tester;

  /// The configuration which should used for the test.
  final GoldenConfiguration configuration;

  /// Whether to expand scrollables.
  ///
  /// To limit the list of scrollables that are expanded specify [scrollables].
  ///
  /// You can either specify [expand] or [shrink].
  final bool expand;

  /// A list of scrollables used to expand the testing surface.
  ///
  /// This list is only considered if [expand] is set to true.
  final List<ScrollableState> scrollables;

  /// The finder which should be used to shrink the testing surface to.
  ///
  /// You can either specify [expand] or [shrink].
  final Finder shrink;

  /// The finder which is used to compare to the golden file.
  ///
  /// This finder must target a [RepaintBoundary].
  final Finder finder;

  @override
  String toString() {
    return 'GoldenMatchInput{tester: $tester, configuration: $configuration, expand: $expand, scrollables: $scrollables, shrink: $shrink, finder: $finder}';
  }
}

class GoldenInputMatcher extends AsyncMatcher {
  GoldenInputMatcher(this.name);

  final String name;

  @override
  Description describe(Description description) {
    return description.add('one widget whose rasterized images match golden images of "$name"');
  }

  @override
  Future<String> matchAsync(dynamic item) async {
    assert(item is List<GoldenMatchInput>);

    final List<GoldenMatchInput> inputs = item as List<GoldenMatchInput>;

    for (GoldenMatchInput input in inputs) {
      if (input.shrink != null) {
        await input.tester.shrinkSurfaceWithinConstraints(input.shrink, input.configuration.constraints);
      } else if (input.scrollables != null) {
        await input.tester.expandSurfaceWithinConstraints(input.scrollables, input.configuration.constraints);
      } else {
        final List<ScrollableState> scrollableStates = find
            .byType(Scrollable)
            .evaluate()
            .map<ScrollableState>((Element element) {
              return (element as StatefulElement).state as ScrollableState;
            })
            .where((ScrollableState scrollableState) => scrollableState.position.extentAfter.isFinite)
            .toList(growable: false);
        await input.tester.expandSurfaceWithinConstraints(scrollableStates, input.configuration.constraints);
      }

      final Finder effectiveFinder =
          input.finder ?? find.byWidgetPredicate((Widget widget) => widget is RepaintBoundary).first;

      // TODO setting the device pixel ratio is sometimes useless
      // Tracked at https://github.com/flutter/flutter/issues/58226
      input.tester.binding.window.devicePixelRatioTestValue = input.configuration.pixelRatio;

      // Calculate window size based on the render view size
      input.tester.binding.window.physicalSizeTestValue =
          input.tester.binding.renderView.size * input.configuration.pixelRatio;

      await Goldens.configuration.primeAssets?.call(input.tester);
      await input.tester.pump();

      final String fileName = Goldens.configuration.fileNameFactory(name, input.configuration);
      final String result = await matchesGoldenFile(fileName).matchAsync(effectiveFinder) as String;

      if (result != null) {
        return result;
      }
    }

    return null;
  }
}

GoldenInputMatcher matchesGoldens(String name) {
  return GoldenInputMatcher(name);
}

// TODO goal: expect(tester.getGoldens([phone.looseHeight()], scrollables: [primaryScrollable]), matchGoldenFiles(name: 'stream'))
// TODO goal: expect(tester.getGoldens([phone.looseHeight()], shrink: find.byType(ShortcastCard))), matchGoldenFiles(name: 'shortcast'))
