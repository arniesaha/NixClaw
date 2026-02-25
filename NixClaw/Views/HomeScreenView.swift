/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// HomeScreenView.swift
//
// Multi-mode landing page for NixClaw.
// Lets users choose between glasses, audio-only, or iPhone camera modes.
//

import MWDATCore
import SwiftUI

struct HomeScreenView: View {
  @ObservedObject var viewModel: WearablesViewModel
  @EnvironmentObject private var appConfig: AppConfig
  #if DEBUG
  @EnvironmentObject private var debugMenuViewModel: DebugMenuViewModel
  #endif
  var onSelectAudioOnly: () -> Void
  var onSelectiPhoneCamera: () -> Void

  @State private var showSettings = false

  var body: some View {
    ZStack {
      Color(red: 0.08, green: 0.08, blue: 0.10).edgesIgnoringSafeArea(.all)

      VStack(spacing: 12) {
        HStack {
          Spacer()
          Button {
            showSettings = true
          } label: {
            Image(systemName: "gearshape")
              .resizable()
              .aspectRatio(contentMode: .fit)
              .foregroundColor(Color(white: 0.6))
              .frame(width: 22, height: 22)
          }
        }

        Spacer()

        Image(.nixClawIcon)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: 120)
          .clipShape(RoundedRectangle(cornerRadius: 24))

        Text("NixClaw")
          .font(.system(size: 28, weight: .bold))
          .foregroundColor(.white)

        Text("Your AI assistant — through glasses, phone, or just voice")
          .font(.system(size: 15))
          .foregroundColor(.gray)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 12)

        VStack(spacing: 12) {
          HomeTipItemView(
            resource: .smartGlassesIcon,
            title: "Smart Glasses",
            text: "Stream video from your Meta Ray-Ban glasses for visual AI."
          )
          HomeTipItemView(
            resource: .soundIcon,
            title: "Audio Only",
            text: "Voice conversations with AI using any audio device — AirPods, speakers, or built-in mic."
          )
          HomeTipItemView(
            resource: .walkingIcon,
            title: "iPhone Camera",
            text: "Use your iPhone camera for visual AI without glasses."
          )
        }

        Spacer()

        VStack(spacing: 12) {
          CustomButton(
            title: "Audio Only",
            style: .primary,
            isDisabled: false
          ) {
            onSelectAudioOnly()
          }

          CustomButton(
            title: "iPhone Camera",
            style: .secondary,
            isDisabled: false
          ) {
            onSelectiPhoneCamera()
          }

          CustomButton(
            title: viewModel.registrationState == .registering ? "Connecting..." : "Connect Glasses",
            style: .secondary,
            isDisabled: viewModel.registrationState == .registering
          ) {
            viewModel.connectGlasses()
          }
        }
      }
      .padding(.all, 24)
    }
    .sheet(isPresented: $showSettings) {
      settingsSheet
    }
  }

  @ViewBuilder
  private var settingsSheet: some View {
    #if DEBUG
    SettingsView()
      .environmentObject(appConfig)
      .environmentObject(debugMenuViewModel)
    #else
    SettingsView()
      .environmentObject(appConfig)
    #endif
  }

}

struct HomeTipItemView: View {
  let resource: ImageResource
  let title: String
  let text: String

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(resource)
        .resizable()
        .renderingMode(.template)
        .foregroundColor(.white)
        .aspectRatio(contentMode: .fit)
        .frame(width: 24)
        .padding(.leading, 4)
        .padding(.top, 4)

      VStack(alignment: .leading, spacing: 6) {
        Text(title)
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(.white)

        Text(text)
          .font(.system(size: 15))
          .foregroundColor(.gray)
      }
      Spacer()
    }
  }
}
