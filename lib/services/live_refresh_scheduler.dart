import 'dart:async';

/// Coalesces change bursts without parallel cache fetches. No queue mutation.
class LiveRefreshScheduler {
  final Future<void> Function() refresh;
  final bool Function() active;
  Timer? _debounce;
  bool _busy = false, _dirty = false, _disposed = false;
  LiveRefreshScheduler({required this.refresh, required this.active});
  void request() {
    if (_disposed || !active()) return;
    _dirty = true;
    _debounce ??= Timer(const Duration(milliseconds: 150), () {
      _debounce = null;
      unawaited(_drain());
    });
  }

  Future<void> _drain() async {
    if (_busy || _disposed || !active()) return;
    _busy = true;
    try {
      while (_dirty && !_disposed && active()) {
        _dirty = false;
        try {
          await refresh();
        } catch (_) {/* The next event/poll retries. */}
      }
    } finally {
      _busy = false;
    }
  }

  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _dirty = false;
  }
}
