/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// StreamView.swift
//
// Main UI for video streaming from Meta wearable devices using the DAT SDK.
// This view demonstrates the complete streaming API: video streaming with real-time display, photo capture,
// and error handling. Extended with Gemini Live AI assistant integration.
//

import MWDATCore
import SwiftUI

struct StreamView: View {
  @ObservedObject var viewModel: StreamSessionViewModel
  @ObservedObject var wearablesVM: WearablesViewModel
  @ObservedObject var geminiVM: GeminiSessionViewModel

  var body: some View {
    ZStack {
      // Black background for letterboxing/pillarboxing
      Color.black
        .edgesIgnoringSafeArea(.all)

      // Audio-only mode UI
      if geminiVM.isAudioOnlyMode {
        AudioOnlyView(geminiVM: geminiVM)
      }
      // Video backdrop (only shown if not audio-only mode)
      else if let videoFrame = viewModel.currentVideoFrame, viewModel.hasReceivedFirstFrame {
        GeometryReader { geometry in
          Image(uiImage: videoFrame)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .edgesIgnoringSafeArea(.all)
      } else if !geminiVM.isAudioOnlyMode {
        ProgressView()
          .scaleEffect(1.5)
          .foregroundColor(.white)
      }

      // Gemini status overlay (top) + speaking indicator
      // Skip this overlay in audio-only mode (AudioOnlyView has its own UI)
      if geminiVM.isGeminiActive && !geminiVM.isAudioOnlyMode {
        VStack {
          GeminiStatusBar(geminiVM: geminiVM)
          Spacer()

          VStack(spacing: 8) {
            if !geminiVM.userTranscript.isEmpty || !geminiVM.aiTranscript.isEmpty {
              TranscriptView(
                userText: geminiVM.userTranscript,
                aiText: geminiVM.aiTranscript
              )
            }

            ToolCallStatusView(status: geminiVM.toolCallStatus)

            if geminiVM.isModelSpeaking {
              HStack(spacing: 8) {
                Image(systemName: "speaker.wave.2.fill")
                  .foregroundColor(.white)
                  .font(.system(size: 14))
                SpeakingIndicator()
              }
              .padding(.horizontal, 16)
              .padding(.vertical, 8)
              .background(Color.black.opacity(0.5))
              .cornerRadius(20)
            }
          }
          .padding(.bottom, 80)
        }
        .padding(.all, 24)
      }

      // Bottom controls layer
      VStack {
        Spacer()
        ControlsView(viewModel: viewModel, geminiVM: geminiVM)
      }
      .padding(.all, 24)
    }
    .onDisappear {
      Task {
        if viewModel.streamingStatus != .stopped {
          await viewModel.stopSession()
        }
        if geminiVM.isGeminiActive {
          if geminiVM.isAudioOnlyMode {
            geminiVM.stopAudioOnlySession()
          } else {
            geminiVM.stopSession()
          }
        }
      }
    }
    // Show captured photos from DAT SDK in a preview sheet
    .sheet(isPresented: $viewModel.showPhotoPreview) {
      if let photo = viewModel.capturedPhoto {
        PhotoPreviewView(
          photo: photo,
          onDismiss: {
            viewModel.dismissPhotoPreview()
          }
        )
      }
    }
    // Gemini error alert
    .alert("AI Assistant", isPresented: Binding(
      get: { geminiVM.errorMessage != nil },
      set: { if !$0 { geminiVM.errorMessage = nil } }
    )) {
      Button("OK") { geminiVM.errorMessage = nil }
    } message: {
      Text(geminiVM.errorMessage ?? "")
    }
  }
}

// Audio-only mode view (no video, just voice interface)
struct AudioOnlyView: View {
  @ObservedObject var geminiVM: GeminiSessionViewModel

  var body: some View {
    VStack(spacing: 24) {
      Spacer()

      // Microphone animation
      ZStack {
        Circle()
          .fill(Color.blue.opacity(0.2))
          .frame(width: 180, height: 180)
          .scaleEffect(geminiVM.isModelSpeaking ? 1.2 : 1.0)
          .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: geminiVM.isModelSpeaking)

        Circle()
          .fill(Color.blue.opacity(0.3))
          .frame(width: 140, height: 140)

        Image(systemName: geminiVM.isModelSpeaking ? "waveform" : "mic.fill")
          .font(.system(size: 60))
          .foregroundColor(.white)
      }

      VStack(spacing: 8) {
        Text("Audio Only Mode")
          .font(.title2)
          .fontWeight(.semibold)
          .foregroundColor(.white)

        Text(geminiVM.isModelSpeaking ? "Speaking..." : "Listening...")
          .font(.subheadline)
          .foregroundColor(.white.opacity(0.7))

        // Session duration
        Text(formatDuration(geminiVM.sessionDuration))
          .font(.caption)
          .monospacedDigit()
          .foregroundColor(.white.opacity(0.5))
      }

      // Transcripts
      if !geminiVM.userTranscript.isEmpty || !geminiVM.aiTranscript.isEmpty {
        TranscriptView(
          userText: geminiVM.userTranscript,
          aiText: geminiVM.aiTranscript
        )
        .padding(.horizontal)
      }

      ToolCallStatusView(status: geminiVM.toolCallStatus)

      Spacer()

      // Stop button
      CustomButton(
        title: "Stop Audio Session",
        style: .destructive,
        isDisabled: false
      ) {
        geminiVM.stopAudioOnlySession()
      }
      .padding(.horizontal, 24)
      .padding(.bottom, 24)
    }
  }

  private func formatDuration(_ duration: TimeInterval) -> String {
    let minutes = Int(duration) / 60
    let seconds = Int(duration) % 60
    return String(format: "%d:%02d", minutes, seconds)
  }
}

// Extracted controls for clarity
struct ControlsView: View {
  @ObservedObject var viewModel: StreamSessionViewModel
  @ObservedObject var geminiVM: GeminiSessionViewModel

  var body: some View {
    // Don't show controls in audio-only mode (it has its own UI)
    if geminiVM.isAudioOnlyMode {
      EmptyView()
    } else {
      // Controls row - simplified: just stop streaming and camera
      HStack(spacing: 12) {
        CustomButton(
          title: "Stop streaming",
          style: .destructive,
          isDisabled: false
        ) {
          Task {
            await viewModel.stopSession()
          }
        }

        // Photo button (glasses mode only — DAT SDK capture)
        if viewModel.streamingMode == .glasses {
          CircleButton(icon: "camera.fill", text: nil) {
            viewModel.capturePhoto()
          }
        }
      }
    }
  }
}
