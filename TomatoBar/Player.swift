import AVFoundation
import SwiftUI

class TBPlayer: ObservableObject {
    private var dingSound: AVAudioPlayer

    @AppStorage("dingVolume") var dingVolume: Double = 1.0 {
        didSet {
            setVolume(dingSound, dingVolume)
        }
    }

    private func setVolume(_ sound: AVAudioPlayer, _ volume: Double) {
        sound.setVolume(Float(volume), fadeDuration: 0)
    }

    init() {
        let dingSoundAsset = NSDataAsset(name: "ding")
        do {
            dingSound = try AVAudioPlayer(data: dingSoundAsset!.data, fileTypeHint: AVFileType.wav.rawValue)
        } catch {
            fatalError("Error initializing players: \(error)")
        }
        dingSound.prepareToPlay()
        setVolume(dingSound, dingVolume)
    }

    func playDing() {
        dingSound.play()
    }
}
