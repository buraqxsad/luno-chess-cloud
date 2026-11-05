import 'package:flutter/foundation.dart';

import 'product_crash_reporter.dart';

/// Release handlers receive only fixed messages, never exception/stack payloads.
class ProductErrorHandlers {
  ProductErrorHandlers({
    ProductCrashReporter? reporter,
    this.release = kReleaseMode,
    FlutterExceptionHandler? frameworkHandler,
    bool Function(Object, StackTrace)? asyncHandler,
    void Function(FlutterErrorDetails)? presentError,
  }) : _reporter = reporter ?? ProductCrashReporter.instance,
       _frameworkHandler = frameworkHandler,
       _asyncHandler = asyncHandler,
       _presentError = presentError ?? FlutterError.presentError;

  final ProductCrashReporter _reporter;
  final bool release;
  final FlutterExceptionHandler? _frameworkHandler;
  final bool Function(Object, StackTrace)? _asyncHandler;
  final void Function(FlutterErrorDetails) _presentError;

  void framework(FlutterErrorDetails details) {
    _reporter.report(
      details.exception,
      details.stack,
      source: ProductErrorSource.framework,
    );
    (_frameworkHandler ?? _presentError)(
      release
          ? FlutterErrorDetails(
            exception: StateError('Luno framework failure'),
            library: 'Luno Chess',
            silent: details.silent,
          )
          : details,
    );
  }

  bool asynchronous(Object error, StackTrace stack) {
    _reporter.report(error, stack, source: ProductErrorSource.asyncError);
    if (!release) return _asyncHandler?.call(error, stack) ?? false;
    final safeError = StateError('Luno asynchronous failure');
    if (_asyncHandler?.call(safeError, StackTrace.empty) == true) return true;
    // Handle by reporting safely; returning false would let the engine print
    // the original private exception and stack despite our sanitized sink.
    _presentError(
      FlutterErrorDetails(exception: safeError, library: 'Luno Chess'),
    );
    return true;
  }
}
