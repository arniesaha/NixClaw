/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// NixClawApp.swift
//
// Main entry point for NixClaw — a multi-mode AI assistant app.
// Supports Meta Ray-Ban smart glasses (video + audio), iPhone camera mode,
// and audio-only mode with any audio device.
//

import Foundation
import MWDATCore
import SwiftUI

#if DEBUG
import MWDATMockDevice
#endif

@main
struct NixClawApp: App {
  #if DEBUG
  // Debug menu for simulating device connections during development
  @StateObject private var debugMenuViewModel = DebugMenuViewModel(mockDeviceKit: MockDeviceKit.shared)
  #endif
  @StateObject private var appConfig = AppConfig.shared
  @StateObject private var backgroundModeManager = BackgroundModeManager()
  private let wearables: WearablesInterface
  @StateObject private var wearablesViewModel: WearablesViewModel

  init() {
    // Must register before app finishes launching
    BackgroundModeManager.registerBackgroundTasks()

    do {
      try Wearables.configure()
    } catch {
      #if DEBUG
      NSLog("[NixClaw] Failed to configure Wearables SDK: \(error)")
      #endif
    }
    let wearables = Wearables.shared
    self.wearables = wearables
    self._wearablesViewModel = StateObject(wrappedValue: WearablesViewModel(wearables: wearables))
  }

  var body: some Scene {
    WindowGroup {
      Group {
        if appConfig.needsSetup {
          // Required config missing — show first-launch setup wizard
          SetupWizardView()
        } else {
          // Main app view with access to the shared Wearables SDK instance
          // The Wearables.shared singleton provides the core DAT API
          MainAppView(wearables: Wearables.shared, viewModel: wearablesViewModel)
            // Show error alerts for view model failures
            .alert("Error", isPresented: $wearablesViewModel.showError) {
              Button("OK") {
                wearablesViewModel.dismissError()
              }
            } message: {
              Text(wearablesViewModel.errorMessage)
            }
            #if DEBUG
            .sheet(isPresented: $debugMenuViewModel.showDebugMenu) {
              MockDeviceKitView(viewModel: debugMenuViewModel.mockDeviceKitViewModel)
            }
            .overlay {
              DebugMenuView(debugMenuViewModel: debugMenuViewModel)
            }
            #endif
        }
      }
      .environmentObject(appConfig)
      .environmentObject(backgroundModeManager)

      // Registration view handles the flow for connecting to the glasses via Meta AI
      RegistrationView(viewModel: wearablesViewModel)
    }
  }
}
