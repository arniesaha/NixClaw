import SwiftUI

/// Visual feedback when a photo/frame is captured for AI analysis
/// Shows a brief flash animation + thumbnail preview similar to iOS screenshot
struct CaptureFlashView: View {
  @Binding var isVisible: Bool
  var capturedImage: UIImage?
  
  @State private var flashOpacity: Double = 0
  @State private var thumbnailOffset: CGFloat = 100
  @State private var thumbnailOpacity: Double = 0
  @State private var thumbnailScale: CGFloat = 0.8
  
  var body: some View {
    ZStack {
      // Full-screen white flash
      Color.white
        .opacity(flashOpacity)
        .edgesIgnoringSafeArea(.all)
        .allowsHitTesting(false)
      
      // Thumbnail preview (bottom-left, like iOS screenshot)
      if let image = capturedImage {
        VStack {
          Spacer()
          HStack {
            ThumbnailPreview(image: image)
              .offset(x: thumbnailOffset)
              .opacity(thumbnailOpacity)
              .scaleEffect(thumbnailScale)
            Spacer()
          }
          .padding(.leading, 16)
          .padding(.bottom, 100)
        }
      }
    }
    .onChange(of: isVisible) { _, newValue in
      if newValue {
        playAnimation()
      }
    }
  }
  
  private func playAnimation() {
    // Reset state
    flashOpacity = 0
    thumbnailOffset = 100
    thumbnailOpacity = 0
    thumbnailScale = 0.8
    
    // Flash animation
    withAnimation(.easeIn(duration: 0.1)) {
      flashOpacity = 0.8
    }
    
    // Flash fade out
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      withAnimation(.easeOut(duration: 0.15)) {
        flashOpacity = 0
      }
    }
    
    // Thumbnail slide in
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
      withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
        thumbnailOffset = 0
        thumbnailOpacity = 1
        thumbnailScale = 1
      }
    }
    
    // Thumbnail fade out after delay
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
      withAnimation(.easeOut(duration: 0.3)) {
        thumbnailOpacity = 0
        thumbnailOffset = -20
      }
      
      // Reset visibility flag after animation completes
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        isVisible = false
      }
    }
  }
}

/// Thumbnail with border and shadow (like iOS screenshot preview)
struct ThumbnailPreview: View {
  let image: UIImage
  
  var body: some View {
    VStack(spacing: 4) {
      Image(uiImage: image)
        .resizable()
        .aspectRatio(contentMode: .fill)
        .frame(width: 80, height: 100)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
          RoundedRectangle(cornerRadius: 8)
            .stroke(Color.white.opacity(0.5), lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
      
      // "Sent to AI" label
      HStack(spacing: 4) {
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 10))
        Text("Sent")
          .font(.system(size: 10, weight: .medium))
      }
      .foregroundColor(.white)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(Color.green.opacity(0.8))
      .clipShape(Capsule())
    }
  }
}

#Preview {
  ZStack {
    Color.black.edgesIgnoringSafeArea(.all)
    CaptureFlashView(
      isVisible: .constant(true),
      capturedImage: UIImage(systemName: "photo")
    )
  }
}
