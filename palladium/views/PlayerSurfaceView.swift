import AVKit
import SwiftUI

/// SwiftUI `VideoPlayer`는 자체 재생 컨트롤을 함께 그려 프레임 이동·스크럽 바 같은 우리 컨트롤과 겹치므로, AppKit `AVPlayerView`를 컨트롤 없이 감싼다.
struct PlayerSurfaceView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context _: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.controlsStyle = .none
        playerView.player = player
        return playerView
    }

    func updateNSView(_ playerView: AVPlayerView, context _: Context) {
        playerView.player = player
    }
}
