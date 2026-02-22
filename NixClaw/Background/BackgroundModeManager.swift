import UIKit
import Combine
import BackgroundTasks

/// Manages app lifecycle and background mode transitions
@MainActor
class BackgroundModeManager: ObservableObject {

  static let cleanupTaskIdentifier = "com.nixclaw.app.cleanup"

  @Published var isInBackground = false

  private var cancellables = Set<AnyCancellable>()

  init() {
    setupLifecycleObservers()
  }

  private func setupLifecycleObservers() {
    // App entering background
    NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.handleEnterBackground()
      }
      .store(in: &cancellables)

    // App returning to foreground
    NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.handleEnterForeground()
      }
      .store(in: &cancellables)

    // App becoming active
    NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.handleBecomeActive()
      }
      .store(in: &cancellables)
  }

  // MARK: - BGTaskScheduler

  /// Register the background cleanup task. Must be called before app finishes launching.
  nonisolated static func registerBackgroundTasks() {
    BGTaskScheduler.shared.register(
      forTaskWithIdentifier: cleanupTaskIdentifier,
      using: nil
    ) { task in
      guard let task = task as? BGProcessingTask else { return }
      handleCleanupTask(task)
    }
    NSLog("[BackgroundMode] Registered background cleanup task")
  }

  /// Schedule the cleanup task to run when the system has resources available.
  func scheduleCleanupTask() {
    let request = BGProcessingTaskRequest(identifier: Self.cleanupTaskIdentifier)
    request.requiresNetworkConnectivity = false
    request.requiresExternalPower = false

    do {
      try BGTaskScheduler.shared.submit(request)
      NSLog("[BackgroundMode] Scheduled cleanup task")
    } catch {
      NSLog("[BackgroundMode] Failed to schedule cleanup task: %@", error.localizedDescription)
    }
  }

  /// Handle the cleanup task when the system wakes the app.
  private nonisolated static func handleCleanupTask(_ task: BGProcessingTask) {
    NSLog("[BackgroundMode] Running cleanup task")

    task.expirationHandler = {
      NSLog("[BackgroundMode] Cleanup task expired before completion")
    }

    // End any stale Live Activities that survived a previous termination
    Task { @MainActor in
      GeminiLiveActivityManager.shared.endActivity()
      NSLog("[BackgroundMode] Cleaned up stale Live Activity")
    }

    task.setTaskCompleted(success: true)
    NSLog("[BackgroundMode] Cleanup task completed")
  }

  // MARK: - Lifecycle

  private func handleEnterBackground() {
    NSLog("[BackgroundMode] App entered background")
    isInBackground = true

    // Schedule cleanup in case the app gets terminated while backgrounded
    scheduleCleanupTask()

    // Post notification for other components
    NotificationCenter.default.post(name: .appDidEnterBackground, object: nil)
  }

  private func handleEnterForeground() {
    NSLog("[BackgroundMode] App entering foreground")
    isInBackground = false

    NotificationCenter.default.post(name: .appWillEnterForeground, object: nil)
  }

  private func handleBecomeActive() {
    NSLog("[BackgroundMode] App became active")

    NotificationCenter.default.post(name: .appDidBecomeActive, object: nil)
  }
}

// MARK: - Notification Names

extension Notification.Name {
  static let appDidEnterBackground = Notification.Name("appDidEnterBackground")
  static let appWillEnterForeground = Notification.Name("appWillEnterForeground")
  static let appDidBecomeActive = Notification.Name("appDidBecomeActive")
}
