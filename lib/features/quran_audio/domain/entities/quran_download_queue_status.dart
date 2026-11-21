/// Lifecycle status definitions for full-Quran download queue and queue items (QA.6).
library;

/// The aggregate lifecycle status of a full-Quran download queue.
enum QuranDownloadQueueStatus {
  /// Queue created or queued for execution, not yet actively processing tracks.
  pending,

  /// Queue worker is actively downloading or verifying Surah audio files sequentially.
  running,

  /// Queue execution was halted by user request or environmental constraint.
  paused,

  /// All 114 Surahs have been successfully verified and saved locally.
  completed,

  /// Queue encountered an unrecoverable error (e.g. disk full, network exhausted).
  failed,

  /// Queue was intentionally aborted by the user.
  cancelled;

  /// Whether this queue is currently occupying an active state.
  /// Matches SQLite partial unique index: `status IN ('pending', 'running', 'paused')`.
  bool get isActive =>
      this == QuranDownloadQueueStatus.pending ||
      this == QuranDownloadQueueStatus.running ||
      this == QuranDownloadQueueStatus.paused;

  /// Whether the queue has concluded and is no longer processing or resumable without retry.
  bool get isTerminal =>
      this == QuranDownloadQueueStatus.completed ||
      this == QuranDownloadQueueStatus.failed ||
      this == QuranDownloadQueueStatus.cancelled;

  /// Whether the queue can be resumed or retried.
  bool get isResumable =>
      this == QuranDownloadQueueStatus.paused ||
      this == QuranDownloadQueueStatus.failed;

  /// Whether the queue is actively processing.
  bool get isRunning => this == QuranDownloadQueueStatus.running;

  /// Whether the queue is currently paused.
  bool get isPaused => this == QuranDownloadQueueStatus.paused;

  /// Whether the queue has fully completed.
  bool get isCompleted => this == QuranDownloadQueueStatus.completed;

  /// Whether the queue has failed.
  bool get isFailed => this == QuranDownloadQueueStatus.failed;

  /// Whether the queue has been cancelled.
  bool get isCancelled => this == QuranDownloadQueueStatus.cancelled;

  /// Validates whether a state transition from `this` to [target] is permitted.
  bool canTransitionTo(QuranDownloadQueueStatus target) {
    if (this == target) return true; // Idempotent self-transition

    switch (this) {
      case QuranDownloadQueueStatus.pending:
        return target == QuranDownloadQueueStatus.running ||
            target == QuranDownloadQueueStatus.paused ||
            target == QuranDownloadQueueStatus.cancelled;

      case QuranDownloadQueueStatus.running:
        return target == QuranDownloadQueueStatus.paused ||
            target == QuranDownloadQueueStatus.completed ||
            target == QuranDownloadQueueStatus.failed ||
            target == QuranDownloadQueueStatus.cancelled;

      case QuranDownloadQueueStatus.paused:
        return target == QuranDownloadQueueStatus.running ||
            target == QuranDownloadQueueStatus.cancelled;

      case QuranDownloadQueueStatus.failed:
        return target == QuranDownloadQueueStatus.running || // On retry
            target == QuranDownloadQueueStatus.cancelled;

      case QuranDownloadQueueStatus.completed:
        return false; // Terminal final state

      case QuranDownloadQueueStatus.cancelled:
        return false; // Terminal final state
    }
  }

  /// Converts string representation from database to enum.
  static QuranDownloadQueueStatus fromString(String value) {
    switch (value.trim().toLowerCase()) {
      case 'pending':
        return QuranDownloadQueueStatus.pending;
      case 'running':
        return QuranDownloadQueueStatus.running;
      case 'paused':
        return QuranDownloadQueueStatus.paused;
      case 'completed':
        return QuranDownloadQueueStatus.completed;
      case 'failed':
        return QuranDownloadQueueStatus.failed;
      case 'cancelled':
        return QuranDownloadQueueStatus.cancelled;
      default:
        throw ArgumentError.value(
          value,
          'value',
          'Unknown QuranDownloadQueueStatus string value',
        );
    }
  }

  /// Canonical database string representation.
  String toDbString() => name;
}

/// The individual lifecycle status of a Surah track item within a full-Quran queue.
enum QuranDownloadQueueItemStatus {
  /// Awaiting turn in the sequential queue.
  pending,

  /// Currently being downloaded or verified by QA.5 download engine.
  running,

  /// Halted mid-transfer, staging file preserved for resumption.
  paused,

  /// Download completed and verified in QA.5 registry.
  completed,

  /// Download failed after retry exhaustion or environmental error.
  failed,

  /// Download aborted due to queue cancellation.
  cancelled,

  /// Surah was already verified as completed in QA.5 prior to queue run.
  skipped;

  /// Whether this item represents a satisfied completion condition.
  /// Queue completion invariant: `completedItems == totalItems == 114`
  /// iff for all items `item.status.isCompletedOrSkipped == true`.
  bool get isCompletedOrSkipped =>
      this == QuranDownloadQueueItemStatus.completed ||
      this == QuranDownloadQueueItemStatus.skipped;

  /// Whether this item is in a terminal state for the current run.
  bool get isTerminal =>
      this == QuranDownloadQueueItemStatus.completed ||
      this == QuranDownloadQueueItemStatus.failed ||
      this == QuranDownloadQueueItemStatus.cancelled ||
      this == QuranDownloadQueueItemStatus.skipped;

  /// Whether this item is currently actively downloading.
  bool get isRunning => this == QuranDownloadQueueItemStatus.running;

  /// Whether this item is pending execution.
  bool get isPending => this == QuranDownloadQueueItemStatus.pending;

  /// Whether this item is paused.
  bool get isPaused => this == QuranDownloadQueueItemStatus.paused;

  /// Whether this item failed.
  bool get isFailed => this == QuranDownloadQueueItemStatus.failed;

  /// Whether this item was cancelled.
  bool get isCancelled => this == QuranDownloadQueueItemStatus.cancelled;

  /// Whether this item was skipped.
  bool get isSkipped => this == QuranDownloadQueueItemStatus.skipped;

  /// Validates whether a state transition from `this` to [target] is permitted.
  bool canTransitionTo(QuranDownloadQueueItemStatus target) {
    if (this == target) return true; // Idempotent

    switch (this) {
      case QuranDownloadQueueItemStatus.pending:
        return target == QuranDownloadQueueItemStatus.running ||
            target == QuranDownloadQueueItemStatus.paused ||
            target == QuranDownloadQueueItemStatus.cancelled ||
            target == QuranDownloadQueueItemStatus.skipped;

      case QuranDownloadQueueItemStatus.running:
        return target == QuranDownloadQueueItemStatus.completed ||
            target == QuranDownloadQueueItemStatus.paused ||
            target == QuranDownloadQueueItemStatus.failed ||
            target == QuranDownloadQueueItemStatus.cancelled;

      case QuranDownloadQueueItemStatus.paused:
        return target == QuranDownloadQueueItemStatus.running ||
            target == QuranDownloadQueueItemStatus.failed ||
            target == QuranDownloadQueueItemStatus.cancelled;

      case QuranDownloadQueueItemStatus.failed:
        return target == QuranDownloadQueueItemStatus.pending || // On retry
            target == QuranDownloadQueueItemStatus.cancelled;

      case QuranDownloadQueueItemStatus.completed:
      case QuranDownloadQueueItemStatus.cancelled:
      case QuranDownloadQueueItemStatus.skipped:
        return false; // Terminal states
    }
  }

  /// Converts string representation from database to enum.
  static QuranDownloadQueueItemStatus fromString(String value) {
    switch (value.trim().toLowerCase()) {
      case 'pending':
        return QuranDownloadQueueItemStatus.pending;
      case 'running':
        return QuranDownloadQueueItemStatus.running;
      case 'paused':
        return QuranDownloadQueueItemStatus.paused;
      case 'completed':
        return QuranDownloadQueueItemStatus.completed;
      case 'failed':
        return QuranDownloadQueueItemStatus.failed;
      case 'cancelled':
        return QuranDownloadQueueItemStatus.cancelled;
      case 'skipped':
        return QuranDownloadQueueItemStatus.skipped;
      default:
        throw ArgumentError.value(
          value,
          'value',
          'Unknown QuranDownloadQueueItemStatus string value',
        );
    }
  }

  /// Canonical database string representation.
  String toDbString() => name;
}
