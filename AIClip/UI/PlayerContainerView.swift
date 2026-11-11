import AVFoundation
import SwiftUI

struct PlayerContainerView: View {
    @Environment(EditorStore.self) private var store

    var body: some View {
        ZStack {
            Color.black
            if store.hasVideo {
                PlayerLayerView(player: store.player.player)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 42, weight: .light))
                        .foregroundStyle(EditorTheme.accent)
                    Text("从相册导入视频，开始剪辑")
                        .font(.body)
                        .foregroundStyle(EditorTheme.secondary)
                }
                .padding()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }
}

final class PlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
