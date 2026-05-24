// Copyright 2026 David Sansome
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import PromiseKit
import SwiftUI
import UIKit
import WaniKaniAPI

// SwiftUI rewrite of OfflineAudioViewController. Drives services.offlineAudio directly; polls the
// download Progress for the status row.

@available(iOS 15.0, *)
final class OfflineAudioModel: ObservableObject {
  struct VoiceActor: Identifiable {
    let id: Int64
    let title: String
    let subtitle: String
  }

  private let services: TKMServices
  let voiceActors: [VoiceActor]

  @Published var enabled: Bool
  @Published var cellular: Bool
  @Published var selectedActors: Set<Int64>
  @Published var statusTitle = "Up to date"
  @Published var statusSubtitle: String?
  @Published var cacheSize = "…"
  @Published var showDeletePrompt = false

  private var progress: Progress?
  private var timer: Timer?

  init(services: TKMServices) {
    self.services = services
    enabled = Settings.offlineAudio
    cellular = Settings.offlineAudioCellular
    selectedActors = Settings.offlineAudioVoiceActors
    voiceActors = services.localCachingClient.getVoiceActors().map { actor in
      var subtitle = actor.description_p
      switch actor.gender {
      case .male: subtitle += " - male"
      case .female: subtitle += " - female"
      default: break
      }
      return VoiceActor(id: actor.id, title: actor.name, subtitle: subtitle)
    }
    progress = services.offlineAudio.lastProgress
    refreshStatus()
    updateCacheSize()
    timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
      self?.refreshStatus()
    }
  }

  deinit { timer?.invalidate() }

  func setEnabled(_ on: Bool) {
    enabled = on
    Settings.offlineAudio = on
    if on, selectedActors.isEmpty {
      selectedActors = Set(voiceActors.map { $0.id })
      Settings.offlineAudioVoiceActors = selectedActors
    }
    settingsChanged()
    if !on { showDeletePrompt = true }
  }

  func setCellular(_ on: Bool) {
    cellular = on
    Settings.offlineAudioCellular = on
    settingsChanged()
  }

  func toggleActor(_ id: Int64) {
    if selectedActors.contains(id) { selectedActors.remove(id) } else { selectedActors.insert(id) }
    Settings.offlineAudioVoiceActors = selectedActors
    settingsChanged()
  }

  func deleteDownloaded() {
    firstly { self.services.offlineAudio.deleteAll() }
      .ensure { self.updateCacheSize() }
      .catch { _ in }
  }

  private func settingsChanged() {
    progress = services.offlineAudio.queueDownloads()
    refreshStatus()
  }

  private var isProgressActive: Bool {
    guard let progress = progress else { return false }
    return !progress.isFinished && progress.totalUnitCount != 0
  }

  private func refreshStatus() {
    if isProgressActive, let progress = progress {
      statusTitle = "Downloading audio…"
      statusSubtitle = "\(Int(progress.fractionCompleted * 100))%"
    } else {
      statusTitle = "Up to date"
      statusSubtitle = nil
    }
  }

  private func updateCacheSize() {
    firstly { services.offlineAudio.cacheDirectorySize() }
      .map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
      .done { size in DispatchQueue.main.async { self.cacheSize = size } }
      .catch { _ in }
  }
}

@available(iOS 15.0, *)
struct OfflineAudioScreen: View {
  @StateObject var model: OfflineAudioModel

  var body: some View {
    List {
      Section {
        Toggle("Enable offline audio",
               isOn: Binding(get: { model.enabled }, set: { model.setEnabled($0) }))
        Toggle("Download over cellular",
               isOn: Binding(get: { model.cellular }, set: { model.setCellular($0) }))
          .disabled(!model.enabled)
      } footer: {
        Text("Download audio to your device so it plays without delay online and is available offline.")
      }

      Section("Voice actors") {
        ForEach(model.voiceActors) { actor in
          Toggle(isOn: Binding(get: { model.selectedActors.contains(actor.id) },
                               set: { _ in model.toggleActor(actor.id) })) {
            SubtitleLabel(actor.title, actor.subtitle)
          }
          .disabled(!model.enabled)
        }
      }

      Section {
        HStack {
          Text(model.statusTitle)
          Spacer()
          if let sub = model.statusSubtitle { Text(sub).foregroundStyle(.secondary) }
        }
        HStack {
          Text("Cache size")
          Spacer()
          Text(model.cacheSize).foregroundStyle(.secondary)
        }
      } header: {
        Text("Status")
      } footer: {
        Text("Downloads will continue in the background.")
      }
    }
    .alert("Delete offline audio?", isPresented: $model.showDeletePrompt) {
      Button("Keep", role: .cancel) {}
      Button("Delete", role: .destructive) { model.deleteDownloaded() }
    } message: {
      Text("Free up space? You can download it again later.")
    }
  }
}
