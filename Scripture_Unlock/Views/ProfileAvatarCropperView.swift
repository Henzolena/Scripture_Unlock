import SwiftUI
import UIKit

private enum AvatarCropperError: LocalizedError {
    case encodingFailed

    var errorDescription: String? {
        "The cropped photo could not be prepared."
    }
}

struct ProfileAvatarCropperView: View {
    let image: UIImage
    let onCancel: () -> Void
    let onCrop: (Data) -> Void

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var statusMessage = ""
    @State private var isPreparing = false

    private let outputSize: CGFloat = 640
    private let maxScale: CGFloat = 5

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let cropSize = min(proxy.size.width - 40, 340)
                let baseSize = imageDisplaySize(for: cropSize)

                VStack(spacing: 22) {
                    Spacer(minLength: 18)

                    cropCanvas(cropSize: cropSize, baseSize: baseSize)

                    VStack(spacing: 8) {
                        Text("Drag to position. Pinch to zoom.")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DesignSystem.slate600)
                        zoomSlider(cropSize: cropSize, baseSize: baseSize)
                        if !statusMessage.isEmpty {
                            Text(statusMessage)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(DesignSystem.danger)
                                .multilineTextAlignment(.center)
                        }
                    }

                    HStack(spacing: 10) {
                        AppActionButton(
                            title: "Reset",
                            icon: "arrow.counterclockwise",
                            style: .neutral,
                            size: .compact
                        ) {
                            resetCrop()
                        }

                        AppActionButton(
                            title: "Use Photo",
                            icon: "checkmark",
                            style: .primary,
                            size: .compact,
                            disabled: isPreparing
                        ) {
                            finishCrop(cropSize: cropSize, baseSize: baseSize)
                        }
                    }
                    .padding(.horizontal, 20)

                    Spacer(minLength: 18)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DesignSystem.warmCream.ignoresSafeArea())
            }
            .navigationTitle("Crop Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    AppToolbarTextButton(title: "Cancel", style: .neutral) {
                        onCancel()
                    }
                }
            }
        }
    }

    private func cropCanvas(cropSize: CGFloat, baseSize: CGSize) -> some View {
        let drag = DragGesture()
            .onChanged { value in
                let next = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
                offset = clampedOffset(next, cropSize: cropSize, baseSize: baseSize, scale: scale)
            }
            .onEnded { _ in
                offset = clampedOffset(offset, cropSize: cropSize, baseSize: baseSize, scale: scale)
                lastOffset = offset
            }

        let pinch = MagnificationGesture()
            .onChanged { value in
                scale = min(max(lastScale * value, 1), maxScale)
                offset = clampedOffset(offset, cropSize: cropSize, baseSize: baseSize, scale: scale)
            }
            .onEnded { _ in
                scale = min(max(scale, 1), maxScale)
                offset = clampedOffset(offset, cropSize: cropSize, baseSize: baseSize, scale: scale)
                lastScale = scale
                lastOffset = offset
            }

        return ZStack {
            Circle()
                .fill(Color.black.opacity(0.92))
                .frame(width: cropSize, height: cropSize)

            Image(uiImage: image)
                .resizable()
                .frame(width: baseSize.width * scale, height: baseSize.height * scale)
                .offset(offset)
                .frame(width: cropSize, height: cropSize)
                .clipShape(Circle())

            Circle()
                .stroke(DesignSystem.pastoralGold, lineWidth: 3)
                .frame(width: cropSize, height: cropSize)
                .shadow(color: DesignSystem.pastoralGold.opacity(0.26), radius: 18, x: 0, y: 4)

            cropGuides(cropSize: cropSize)

            if isPreparing {
                Circle()
                    .fill(Color.black.opacity(0.36))
                    .frame(width: cropSize, height: cropSize)
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(width: cropSize, height: cropSize)
        .contentShape(Circle())
        .gesture(drag)
        .simultaneousGesture(pinch)
        .padding(.vertical, 8)
    }

    private func zoomSlider(cropSize: CGFloat, baseSize: CGSize) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "minus.magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DesignSystem.slate400)

            Slider(
                value: Binding(
                    get: { Double(scale) },
                    set: { value in
                        scale = CGFloat(value)
                        offset = clampedOffset(offset, cropSize: cropSize, baseSize: baseSize, scale: scale)
                        lastScale = scale
                        lastOffset = offset
                    }
                ),
                in: 1...Double(maxScale)
            )
            .tint(DesignSystem.pastoralGold)

            Image(systemName: "plus.magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DesignSystem.slate400)
        }
        .padding(.horizontal, 26)
    }

    private func cropGuides(cropSize: CGFloat) -> some View {
        ZStack {
            ForEach([cropSize / 3, cropSize * 2 / 3], id: \.self) { position in
                Rectangle()
                    .fill(.white.opacity(0.20))
                    .frame(width: 1, height: cropSize)
                    .offset(x: position - cropSize / 2)
                Rectangle()
                    .fill(.white.opacity(0.20))
                    .frame(width: cropSize, height: 1)
                    .offset(y: position - cropSize / 2)
            }
        }
        .clipShape(Circle())
        .frame(width: cropSize, height: cropSize)
        .allowsHitTesting(false)
    }

    private func resetCrop() {
        withAnimation(.easeOut(duration: 0.18)) {
            scale = 1
            lastScale = 1
            offset = .zero
            lastOffset = .zero
            statusMessage = ""
        }
    }

    private func finishCrop(cropSize: CGFloat, baseSize: CGSize) {
        isPreparing = true
        statusMessage = ""

        let preparedImage = image
        let currentScale = scale
        let currentOffset = offset

        Task {
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try Self.renderCroppedJPEG(
                        image: preparedImage,
                        cropSize: cropSize,
                        baseSize: baseSize,
                        scale: currentScale,
                        offset: currentOffset,
                        outputSize: outputSize
                    )
                }.value

                await MainActor.run {
                    isPreparing = false
                    onCrop(data)
                }
            } catch {
                await MainActor.run {
                    isPreparing = false
                    statusMessage = error.localizedDescription
                }
            }
        }
    }

    private func imageDisplaySize(for cropSize: CGFloat) -> CGSize {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGSize(width: cropSize, height: cropSize)
        }

        let fillScale = max(cropSize / imageSize.width, cropSize / imageSize.height)
        return CGSize(width: imageSize.width * fillScale, height: imageSize.height * fillScale)
    }

    private func clampedOffset(
        _ proposed: CGSize,
        cropSize: CGFloat,
        baseSize: CGSize,
        scale: CGFloat
    ) -> CGSize {
        let displayWidth = baseSize.width * scale
        let displayHeight = baseSize.height * scale
        let maxX = max(0, (displayWidth - cropSize) / 2)
        let maxY = max(0, (displayHeight - cropSize) / 2)

        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }

    nonisolated private static func renderCroppedJPEG(
        image: UIImage,
        cropSize: CGFloat,
        baseSize: CGSize,
        scale: CGFloat,
        offset: CGSize,
        outputSize: CGFloat
    ) throws -> Data {
        let output = CGSize(width: outputSize, height: outputSize)
        let factor = outputSize / cropSize
        let displayWidth = baseSize.width * scale
        let displayHeight = baseSize.height * scale
        let drawRect = CGRect(
            x: ((cropSize - displayWidth) / 2 + offset.width) * factor,
            y: ((cropSize - displayHeight) / 2 + offset.height) * factor,
            width: displayWidth * factor,
            height: displayHeight * factor
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: output, format: format)
        let cropped = renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: output))
            image.draw(in: drawRect)
        }

        guard let data = cropped.jpegData(compressionQuality: 0.84) else {
            throw AvatarCropperError.encodingFailed
        }

        return data
    }
}
