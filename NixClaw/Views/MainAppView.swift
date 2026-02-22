/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// MainAppView.swift
//
// Central navigation hub supporting three modes: glasses, audio-only, and iPhone camera.
// When unregistered (and no direct mode selected), shows the multi-mode home screen.
//

import MWDATCore
import SwiftUI

enum AppMode {
  case glasses
  case audioOnly
  case iPhoneCamera
}

struct MainAppView: View {
  let wearables: WearablesInterface
  @ObservedObject private var viewModel: WearablesViewModel
  @State private var selectedMode: AppMode?

  init(wearables: WearablesInterface, viewModel: WearablesViewModel) {
    self.wearables = wearables
    self.viewModel = viewModel
  }

  var body: some View {
    if viewModel.registrationState == .registered || viewModel.hasMockDevice {
      StreamSessionView(wearables: wearables, wearablesVM: viewModel)
    } else if let mode = selectedMode {
      StreamSessionView(wearables: wearables, wearablesVM: viewModel, initialMode: mode, onDismiss: {
        selectedMode = nil
      })
    } else {
      HomeScreenView(
        viewModel: viewModel,
        onSelectAudioOnly: {
          selectedMode = .audioOnly
        },
        onSelectiPhoneCamera: {
          selectedMode = .iPhoneCamera
        }
      )
    }
  }
}
