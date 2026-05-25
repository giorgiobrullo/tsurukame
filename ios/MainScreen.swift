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

// SwiftUI rewrite of MainViewController + its embedded tab bar: the home shell. Brand-gradient
// header (avatar / username / level), the SwiftUI dashboard, the sync progress bar, and the search
// bar. `MainModel` owns the sync + notification chain that was in MainViewController; the dashboard
// actions live on `MainHostingController`.

private let kDefaultProfileImageURL =
  "https://cdn.wanikani.com/default-avatar-300x300-20121121.png"

@available(iOS 15.0, *)
final class MainModel: ObservableObject {
  struct UserInfo {
    let username: String
    let level: Int
    let guruKanji: Int
    let avatarURL: URL?
    let onVacation: Bool
  }

  let services: TKMServices
  let dashboardModel = DashboardModel()

  @Published var user: UserInfo?
  @Published var syncing = false
  @Published var syncFraction = 0.0

  private let nd = NotificationDispatcher()
  private var hourlyTimer: Timer?
  private var progressToken: NSKeyValueObservation?

  init(services: TKMServices) { self.services = services }

  func start() {
    nd.add(name: .lccAvailableItemsChanged) { [weak self] _ in self?.refreshData() }
    nd.add(name: .lccRecentMistakesCountChanged) { [weak self] _ in self?.refreshData() }
    nd.add(name: .lccUserInfoChanged) { [weak self] _ in self?.refreshData() }
    nd.add(name: .lccSRSCategoryCountsChanged) { [weak self] _ in self?.refreshData() }
    nd.add(name: UIApplication.didEnterBackgroundNotification) { [weak self] _ in
      self?.cancelHourlyTimer()
    }
    nd.add(name: UIApplication.willEnterForegroundNotification) { [weak self] _ in
      self?.services.localCachingClient.currentHourChanged()
      self?.scheduleHourlyTimer()
    }
    scheduleHourlyTimer()
    refresh(quick: true)
  }

  func refresh(quick: Bool) {
    let progress = Progress(totalUnitCount: 0)
    observeProgress(progress)
    let future = services.localCachingClient.sync(quick: quick, progress: progress)
    refreshData()
    future.finally { [weak self] in self?.refreshData() }
  }

  func refreshData() {
    DispatchQueue.main.async {
      self.dashboardModel.data = DashboardData.make(from: self.services)
      guard let user = self.services.localCachingClient.getUserInfo() else { return }
      let email = Settings.gravatarCustomEmail.isEmpty ? Settings.userEmailAddress
        : Settings.gravatarCustomEmail
      let url = email.isEmpty ? URL(string: kDefaultProfileImageURL) : Self.gravatarURL(email)
      self.user = UserInfo(username: user.username, level: Int(user.level),
                           guruKanji: Int(self.services.localCachingClient.guruKanjiCount),
                           avatarURL: url, onVacation: user.hasVacationStartedAt)
    }
  }

  private func observeProgress(_ progress: Progress) {
    guard !progress.isFinished else { return }
    syncing = true
    syncFraction = 0
    progressToken?.invalidate()
    progressToken = progress.observe(\.fractionCompleted, options: [.new]) { [weak self] p, _ in
      DispatchQueue.main.async {
        self?.syncFraction = p.fractionCompleted
        if p.isFinished {
          self?.syncing = false
          self?.services.radicalCharacterImages.downloadAll()
        }
      }
    }
  }

  private func scheduleHourlyTimer() {
    cancelHourlyTimer()
    let calendar = Calendar.current as NSCalendar
    guard let date = calendar.nextDate(after: Date(), matching: .minute, value: 0,
                                       options: .matchNextTime) else { return }
    hourlyTimer = Timer
      .scheduledTimer(withTimeInterval: date.timeIntervalSinceNow, repeats: false) {
        [weak self] _ in
        self?.services.localCachingClient.currentHourChanged()
        self?.refresh(quick: true)
        self?.scheduleHourlyTimer()
      }
  }

  private func cancelHourlyTimer() {
    hourlyTimer?.invalidate()
    hourlyTimer = nil
  }

  private static func gravatarURL(_ email: String) -> URL? {
    let hash = email.trimmingCharacters(in: .whitespaces).lowercased().sha256()
    let size = 80 * UIScreen.main.scale
    return URL(string:
      "https://www.gravatar.com/avatar/\(hash).jpg?s=\(size)&d=\(kDefaultProfileImageURL)")
  }
}

@available(iOS 15.0, *)
struct MainScreen: View {
  @ObservedObject var model: MainModel
  var onSearch: () -> Void = {}
  var onStats: () -> Void = {}
  var onSettings: () -> Void = {}

  var body: some View {
    VStack(spacing: 0) {
      header
      if model.syncing {
        ProgressView(value: model.syncFraction)
          .progressViewStyle(.linear)
          .tint(.white)
      }
      DashboardScreen(model: model.dashboardModel, onRefresh: { model.refresh(quick: false) })
    }
    .background(Color.tkmBackground.ignoresSafeArea())
  }

  private var header: some View {
    HStack(spacing: 12) {
      AsyncImage(url: model.user?.avatarURL) { image in
        image.resizable().scaledToFill()
      } placeholder: {
        Color.white.opacity(0.2)
      }
      .frame(width: 48, height: 48)
      .clipShape(Circle())
      .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 1))

      VStack(alignment: .leading, spacing: 2) {
        Text(model.user?.username ?? " ")
          .font(.headline)
          .foregroundStyle(.white)
        Text("Level \(model.user?.level ?? 0) · learned \(model.user?.guruKanji ?? 0) kanji")
          .font(.caption)
          .foregroundStyle(.white.opacity(0.9))
      }

      Spacer(minLength: 8)

      if model.user?.onVacation == true {
        Image(systemName: "beach.umbrella.fill").foregroundStyle(.white)
      }
      headerButton("magnifyingglass", action: onSearch)
      headerButton("chart.bar.xaxis", action: onStats)
      headerButton("gearshape", action: onSettings)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(LinearGradient(colors: TKMStyle.radicalGradient.map { Color(cgColor: $0) },
                               startPoint: .top, endPoint: .bottom)
        .ignoresSafeArea(edges: .top))
  }

  private func headerButton(_ systemImage: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 34, height: 34)
        .contentShape(Rectangle())
    }
  }
}
