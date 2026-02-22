/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// StreamSessionView.swift
//
//

import MWDATCore
import SwiftUI

struct StreamSessionView: View {
  let wearables: WearablesInterface
  @ObservedObject private var wearablesViewModel: WearablesViewModel
  @StateObject private var viewModel: StreamSessionViewModel
  @StateObject private var geminiVM = GeminiSessionViewModel()
  private let initialMode: AppMode?
  private let onDismiss: (() -> Void)?

  init(wearables: WearablesInterface, wearablesVM: WearablesViewModel, initialMode: AppMode? = nil, onDismiss: (() -> Void)? = nil) {
    self.wearables = wearables
    self.wearablesViewModel = wearablesVM
    self._viewModel = StateObject(wrappedValue: StreamSessionViewModel(wearables: wearables))
    self.initialMode = initialMode
    self.onDismiss = onDismiss
  }

  var body: some View {
    ZStack {
      if viewModel.isStreaming || geminiVM.isAudioOnlyMode {
        // Full-screen video view with streaming controls (or audio-only mode)
        StreamView(viewModel: viewModel, wearablesVM: wearablesViewModel, geminiVM: geminiVM)
      } else {
        // Pre-streaming setup view with permissions and start button
        NonStreamView(viewModel: viewModel, wearablesVM: wearablesViewModel, geminiVM: geminiVM)
      }
    }
    .task {
      viewModel.geminiSessionVM = geminiVM
      geminiVM.streamingMode = viewModel.streamingMode

      // Auto-launch the selected mode from home screen
      if let mode = initialMode {
        switch mode {
        case .audioOnly:
          await geminiVM.startAudioOnlySession()
        case .iPhoneCamera:
          await viewModel.handleStartIPhone()
        case .glasses:
          break
        }
      }
    }
    .onChange(of: viewModel.streamingMode) { newMode in
      geminiVM.streamingMode = newMode
    }
    .onChange(of: geminiVM.isAudioOnlyMode) { isAudioOnly in
      if !isAudioOnly, initialMode == .audioOnly {
        onDismiss?()
      }
    }
    .onChange(of: viewModel.isStreaming) { isStreaming in
      if !isStreaming, initialMode == .iPhoneCamera {
        onDismiss?()
      }
    }
    .alert("Error", isPresented: $viewModel.showError) {
      Button("OK") {
        viewModel.dismissError()
      }
    } message: {
      Text(viewModel.errorMessage)
    }
  }
}
