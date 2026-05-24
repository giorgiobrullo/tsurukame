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
import SwiftUI
import UIKit
import WaniKaniAPI

// SwiftUI rewrite of FontsViewController (which subclassed DownloadViewController). Drives the font
// downloads via URLSession directly and reuses FontLoader.

@available(iOS 15.0, *)
final class FontsModel: NSObject, ObservableObject, URLSessionDownloadDelegate {
  enum State: Equatable {
    case notInstalled
    case downloading(Double)
    case installedSelected
    case installedNotSelected
  }

  struct Row: Identifiable {
    let id: String // filename
    let title: String
    let sizeBytes: Int64
    let fontName: String
    var state: State
    let screenshot: UIImage?
  }

  private let services: TKMServices
  private lazy var session = URLSession(configuration: .default, delegate: self,
                                        delegateQueue: nil)
  private var tasks = [String: URLSessionDownloadTask]()
  private var progress = [String: Double]()

  @Published var fonts: [Row] = []
  @Published var hasDownloaded = false
  @Published var errorMessage: String?

  init(services: TKMServices) {
    self.services = services
    super.init()
    rebuild()
  }

  func rebuild() {
    fonts = services.fontLoader.allFonts.map { font in
      let filename = font.fileName
      let state: State
      if let fraction = progress[filename] {
        state = .downloading(fraction)
      } else if font.available {
        state = Settings.selectedFonts.contains(filename) ? .installedSelected
          : .installedNotSelected
      } else {
        state = .notInstalled
      }
      return Row(id: filename, title: font.displayName, sizeBytes: Int64(font.sizeBytes),
                 fontName: font.fontName, state: state,
                 screenshot: state == .notInstalled ? font.loadScreenshot() : nil)
    }
    hasDownloaded = FileManager.default.fileExists(atPath: FontLoader.cacheDirectoryPath)
  }

  func tap(_ filename: String) {
    guard let row = fonts.first(where: { $0.id == filename }) else { return }
    switch row.state {
    case .notInstalled: startDownload(filename)
    case .downloading: cancelDownload(filename)
    case .installedNotSelected: setSelected(filename, true)
    case .installedSelected: setSelected(filename, false)
    }
  }

  private func setSelected(_ filename: String, _ selected: Bool) {
    var selectedFonts = Settings.selectedFonts
    if selected { selectedFonts.insert(filename) } else { selectedFonts.remove(filename) }
    Settings.selectedFonts = selectedFonts
    rebuild()
  }

  private func startDownload(_ filename: String) {
    let url = URL(string: "https://tsurukame.app/fonts/\(filename)")!
    let task = session.downloadTask(with: url)
    tasks[filename] = task
    progress[filename] = 0
    task.resume()
    rebuild()
  }

  private func cancelDownload(_ filename: String) {
    tasks[filename]?.cancel()
    tasks[filename] = nil
    progress[filename] = nil
    rebuild()
  }

  func deleteAll() {
    try? FileManager.default.removeItem(atPath: FontLoader.cacheDirectoryPath)
    Settings.selectedFonts = Set<String>()
    for font in services.fontLoader.allFonts { font.didDelete() }
    rebuild()
  }

  // MARK: URLSessionDownloadDelegate

  func urlSession(_: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
                  totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
    guard let filename = downloadTask.originalRequest?.url?.lastPathComponent,
          totalBytesExpectedToWrite > 0 else { return }
    let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
    DispatchQueue.main.async {
      self.progress[filename] = fraction
      self.rebuild()
    }
  }

  func urlSession(_: URLSession, downloadTask: URLSessionDownloadTask,
                  didFinishDownloadingTo location: URL) {
    guard let url = downloadTask.originalRequest?.url,
          let response = downloadTask.response as? HTTPURLResponse else { return }
    let filename = url.lastPathComponent
    if response.statusCode != 200 {
      fail(filename, "HTTP error \(response.statusCode)")
      return
    }
    do {
      try FileManager.default.createDirectory(atPath: FontLoader.cacheDirectoryPath,
                                              withIntermediateDirectories: true)
      let destination = URL(fileURLWithPath: "\(FontLoader.cacheDirectoryPath)/\(filename)")
      try? FileManager.default.removeItem(at: destination)
      try FileManager.default.moveItem(at: location, to: destination)
    } catch {
      fail(filename, error.localizedDescription)
      return
    }
    DispatchQueue.main.async {
      self.services.fontLoader.font(fileName: filename)?.reload()
      self.tasks[filename] = nil
      self.progress[filename] = nil
      var selectedFonts = Settings.selectedFonts
      selectedFonts.insert(filename)
      Settings.selectedFonts = selectedFonts
      self.rebuild()
    }
  }

  func urlSession(_: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard let error = error as? URLError, error.code != .cancelled,
          let filename = task.originalRequest?.url?.lastPathComponent else { return }
    fail(filename, error.localizedDescription)
  }

  private func fail(_ filename: String, _ message: String) {
    DispatchQueue.main.async {
      self.tasks[filename] = nil
      self.progress[filename] = nil
      self.errorMessage = message
      self.rebuild()
    }
  }
}

@available(iOS 15.0, *)
struct FontsScreen: View {
  @StateObject var model: FontsModel
  @State private var showDeleteAll = false

  private let previewText = "私はその人を常に先生と呼んでいた"

  var body: some View {
    List {
      Section {} footer: {
        Text("Choose the fonts to use during reviews. Tsurukame picks a random one from your selection for each word.")
      }

      Section {
        ForEach(model.fonts) { font in
          Button { model.tap(font.id) } label: { row(font) }
        }
      }

      if model.hasDownloaded {
        Section {
          Button("Delete all downloaded fonts", role: .destructive) { showDeleteAll = true }
        }
      }
    }
    .alert("Delete all downloaded fonts", isPresented: $showDeleteAll) {
      Button("Delete", role: .destructive) { model.deleteAll() }
      Button("Cancel", role: .cancel) {}
    }
    .alert("Download error", isPresented: Binding(get: { model.errorMessage != nil },
                                                  set: { if !$0 { model.errorMessage = nil } })) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(model.errorMessage ?? "")
    }
  }

  @ViewBuilder
  private func row(_ font: FontsModel.Row) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 4) {
        Text(font.title).foregroundStyle(Color.tkmLabel)
        switch font.state {
        case .installedSelected, .installedNotSelected:
          Text(previewText)
            .font(.custom(font.fontName, size: 18))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        case .notInstalled:
          if let shot = font.screenshot {
            Image(uiImage: shot).resizable().scaledToFit().frame(height: 22)
              .frame(maxWidth: .infinity, alignment: .leading)
          } else {
            Text(ByteCountFormatter.string(fromByteCount: font.sizeBytes, countStyle: .file))
              .font(.caption).foregroundStyle(.secondary)
          }
        case .downloading:
          EmptyView()
        }
      }
      Spacer()
      trailing(font.state)
    }
  }

  @ViewBuilder
  private func trailing(_ state: FontsModel.State) -> some View {
    switch state {
    case .installedSelected:
      Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.tkmTint)
    case .installedNotSelected:
      Image(systemName: "circle").foregroundStyle(.secondary)
    case .notInstalled:
      Image(systemName: "arrow.down.circle").foregroundStyle(Color.tkmTint)
    case let .downloading(fraction):
      ProgressView(value: fraction).frame(width: 60)
    }
  }
}
