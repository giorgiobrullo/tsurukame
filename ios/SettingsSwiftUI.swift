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
import UserNotifications
import WaniKaniAPI

// SwiftUI rewrite of the Settings hub and its first leaves (Appearance, Audio, Account). The hub
// pushes a mix of migrated SwiftUI screens and not-yet-migrated UIKit screens through
// `SettingsNavigator`, so the migration can proceed screen-by-screen while everything keeps
// working.

// MARK: - Navigator

/// Bridges SwiftUI settings screens to the UIKit navigation stack and to the sub-screens that are
/// still UIKit (or are UIKit choice-list pickers). Holds `services` and a weak presenter.
@available(iOS 15.0, *)
final class SettingsNavigator {
  let services: TKMServices
  weak var presenter: UIViewController?

  init(services: TKMServices) { self.services = services }

  private func push(_ vc: UIViewController) {
    presenter?.navigationController?.pushViewController(vc, animated: true)
  }

  private func present(_ vc: UIViewController) {
    presenter?.present(vc, animated: true)
  }

  // Hub destinations (migrated SwiftUI screens).
  func openAppearance() {
    push(TKMHostingController(title: "Appearance", rootView: AppearanceSettingsScreen(nav: self)))
  }

  func openAudio() {
    push(TKMHostingController(title: "Audio", rootView: AudioSettingsScreen(nav: self)))
  }

  func openAccount() {
    push(TKMHostingController(title: "Account", rootView: AccountSettingsScreen(nav: self)))
  }

  // Hub destinations (migrated SwiftUI screens).
  func openDashboard() {
    push(TKMHostingController(title: "Dashboard", rootView: DashboardSettingsScreen()))
  }

  func openAnki() {
    push(TKMHostingController(title: "Anki mode", rootView: AnkiSettingsScreen(nav: self)))
  }

  func openNotifications() {
    push(TKMHostingController(title: "Notifications", rootView: NotificationsSettingsScreen()))
  }

  func openAnkiTaskType() { push(makeAnkiModeTaskTypeViewController()) }

  func openLessonSettings() {
    push(TKMHostingController(title: "Lessons", rootView: LessonSettingsScreen(nav: self)))
  }

  func openReviewSettings() {
    push(TKMHostingController(title: "Reviews", rootView: ReviewSettingsScreen(nav: self)))
  }

  func openSubjectInfoSettings() {
    push(TKMHostingController(title: "Subject info", rootView: SubjectDetailsSettingsScreen()))
  }

  // Lesson-settings sub-pickers (still UIKit).
  func openLessonOrder() { push(StoryboardScene.LessonOrder.initialScene.instantiate()) }
  func openLessonBatchSize() { push(makeLessonBatchSizeViewController()) }
  func openApprenticeLimit() { push(makeApprenticeLessonLimitViewController()) }

  // Review-settings sub-pickers (still UIKit).
  func openReviewItemsLimit() { push(makeReviewItemsLimitViewController()) }
  func openLeechThreshold() { push(makeLeechThresholdViewController()) }
  func openReviewOrder() { push(makeReviewOrderViewController()) }
  func openTaskOrder() { push(makeTaskOrderViewController()) }
  func openReviewBatchSize() { push(makeReviewBatchSizeViewController()) }

  func showNoJapaneseKeyboardAlert() {
    let device = UIDevice.current.model
    let message = "You must add a Japanese keyboard to your \(device).\nOpen Settings then " +
      "General ⮕ Keyboard ⮕ Keyboards ⮕ Add New Keyboard."
    let ac = UIAlertController(title: "No Japanese keyboard", message: message,
                               preferredStyle: .alert)
    ac.addAction(UIAlertAction(title: "Close", style: .cancel))
    present(ac)
  }

  // Sub-pickers / sub-screens reached from the leaves (still UIKit).
  func openInterfaceStyle() { push(makeInterfaceStyleViewController()) }
  func openFontSize() { push(makeFontSizeViewController()) }

  func openFonts() {
    let vc = StoryboardScene.SelectFonts.initialScene.instantiate()
    vc.setup(services: services)
    push(vc)
  }

  func openOfflineAudio() {
    let vc = StoryboardScene.OfflineAudio.initialScene.instantiate()
    vc.setup(services: services)
    push(vc)
  }

  // Diagnostics / account actions.
  func exportDatabase() {
    present(UIActivityViewController(activityItems: [LocalCachingClient.databaseUrl()],
                                     applicationActivities: nil))
  }

  func clearImageCache() {
    HNKCache.shared().removeAllImages()
    let c = UIAlertController(title: "Image cache cleared", message: nil, preferredStyle: .alert)
    c.addAction(UIAlertAction(title: "OK", style: .default))
    present(c)
  }

  func logOut() {
    let c = UIAlertController(title: "Are you sure?", message: nil, preferredStyle: .alert)
    c.addAction(UIAlertAction(title: "Log out", style: .destructive) { _ in
      NotificationCenter.default.post(name: .logout, object: nil)
    })
    c.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    present(c)
  }
}

/// Hosts the SwiftUI settings hub. Pushed from `MainViewController` on iOS 15+.
@available(iOS 15.0, *)
final class SettingsHostingController: UIHostingController<SettingsHubView>, TKMViewController {
  private let navigator: SettingsNavigator

  var canSwipeToGoBack: Bool { true }

  init(services: TKMServices) {
    let navigator = SettingsNavigator(services: services)
    self.navigator = navigator
    super.init(rootView: SettingsHubView(nav: navigator))
    title = "Settings"
    navigator.presenter = self
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.isNavigationBarHidden = false
  }
}

// MARK: - Hub

@available(iOS 15.0, *)
struct SettingsHubView: View {
  let nav: SettingsNavigator

  private var version: String {
    let info = Bundle.main.infoDictionary
    let v = info?["CFBundleShortVersionString"] as? String ?? "?"
    let b = info?["CFBundleVersion"] as? String ?? "?"
    return "\(v).\(b)"
  }

  var body: some View {
    List {
      Section("Display") {
        iconRow("Appearance", "paintbrush.fill", .purple, action: nav.openAppearance)
        iconRow("Dashboard", "square.grid.2x2.fill", .teal, action: nav.openDashboard)
      }
      Section("Study") {
        iconRow("Lessons", "book.fill", Color(uiColor: TKMStyle.radicalColor1),
                action: nav.openLessonSettings)
        iconRow("Reviews", "rectangle.stack.fill", Color(uiColor: TKMStyle.kanjiColor1),
                action: nav.openReviewSettings)
        iconRow("Anki mode", "square.on.square", .indigo, action: nav.openAnki)
        iconRow("Audio", "speaker.wave.2.fill", .orange, action: nav.openAudio)
        iconRow("Subject info", "character.book.closed.fill",
                Color(uiColor: TKMStyle.vocabularyColor1), action: nav.openSubjectInfoSettings)
      }
      Section("App") {
        iconRow("Notifications", "bell.badge.fill", .red, action: nav.openNotifications)
        iconRow("Account", "person.crop.circle.fill", .blue, action: nav.openAccount)
      }
      Section("Diagnostics") {
        HStack {
          Text("Version")
          Spacer()
          Text(version).foregroundStyle(.secondary).textSelection(.enabled)
        }
        Button("Export local database") { nav.exportDatabase() }
        Button("Clear avatar image cache") { nav.clearImageCache() }
      }
    }
  }

  private func iconRow(_ title: String, _ symbol: String, _ tint: Color,
                       action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: symbol)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(.white)
          .frame(width: 28, height: 28)
          .background(tint)
          .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        Text(title)
          .foregroundStyle(.primary)
        Spacer()
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.tertiary)
      }
    }
  }
}

// MARK: - Appearance

@available(iOS 15.0, *)
struct AppearanceSettingsScreen: View {
  let nav: SettingsNavigator
  @StateObject private var store = SettingsStore()

  var body: some View {
    List {
      Button { nav.openInterfaceStyle() } label: {
        DetailDisclosureRow(title: "Interface style", value: Settings.interfaceStyle.description)
      }
      Button { nav.openFonts() } label: {
        DetailDisclosureRow(title: "Fonts")
      }
      Button { nav.openFontSize() } label: {
        DetailDisclosureRow(title: "Font size",
                            value: Settings.fontSize != 0 ? "\(Int(Settings.fontSize * 100))%" : "")
      }
      Toggle("Show SRS level indicator",
             isOn: store
               .bind(Settings.showSRSLevelIndicator) { Settings.showSRSLevelIndicator = $0 })
    }
    .onAppear { store.refresh() }
  }
}

// MARK: - Audio

@available(iOS 15.0, *)
struct AudioSettingsScreen: View {
  let nav: SettingsNavigator
  @StateObject private var store = SettingsStore()

  var body: some View {
    List {
      Toggle(isOn: store
        .bind(Settings.playAudioAutomatically) { Settings.playAudioAutomatically = $0 }) {
          SubtitleLabel("Play audio automatically", "When you answer correctly")
        }
      Toggle(isOn: store
        .bind(Settings.interruptBackgroundAudio) { Settings.interruptBackgroundAudio = $0 }) {
          SubtitleLabel("Interrupt background audio", "When answer is played automatically")
        }
      Button { nav.openOfflineAudio() } label: {
        DetailDisclosureRow(title: "Offline audio")
      }
    }
  }
}

// MARK: - Account

@available(iOS 15.0, *)
struct AccountSettingsScreen: View {
  let nav: SettingsNavigator
  @StateObject private var store = SettingsStore()

  var body: some View {
    List {
      Section {
        TextField("Email address",
                  text: store
                    .bind(Settings.gravatarCustomEmail) { Settings.gravatarCustomEmail = $0 })
          .keyboardType(.emailAddress)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
      } header: {
        Text("Custom Gravatar email address")
      } footer: {
        Text("Used to load your profile picture if it differs from your WaniKani email.")
      }

      Section {
        Button("Log out", role: .destructive) { nav.logOut() }
      }
    }
  }
}

// MARK: - Dashboard

@available(iOS 15.0, *)
struct DashboardSettingsScreen: View {
  @StateObject private var store = SettingsStore()

  var body: some View {
    List {
      Section {
        Toggle(isOn: store.bind(Settings.showActivityWidget) { Settings.showActivityWidget = $0 }) {
          SubtitleLabel("Activity & streak", "Daily streak and a heatmap of reviews and lessons")
        }
        Toggle(isOn: store.bind(Settings.showAccuracyStat) { Settings.showAccuracyStat = $0 }) {
          SubtitleLabel("Accuracy", "Lifetime review accuracy in the \"All levels\" section")
        }
        Toggle(isOn: store.bind(Settings.showForecastChart) { Settings.showForecastChart = $0 }) {
          SubtitleLabel("Review forecast", "Chart of upcoming reviews over the next 24 hours")
        }
        Toggle(isOn: store
          .bind(Settings.showPreviousLevelGraph) { Settings.showPreviousLevelGraph = $0 }) {
            SubtitleLabel("Previous level graph",
                          "Keep showing the previous level until it's completed")
          }
      } header: {
        Text("Widgets")
      } footer: {
        Text("Choose which widgets appear on the main dashboard.")
      }

      Section {
        Toggle(isOn: store.bind(Settings.catchUpMode) { Settings.catchUpMode = $0 }) {
          SubtitleLabel("Catch-up mode", "Tackle a big backlog one batch at a time")
        }
      } header: {
        Text("Catch-up")
      } footer: {
        Text("When you're behind, show reviews as a manageable batch (your review batch size) instead of the full backlog, and cap each session to that batch.")
      }
    }
  }
}

// MARK: - Anki mode

@available(iOS 15.0, *)
struct AnkiSettingsScreen: View {
  let nav: SettingsNavigator
  @StateObject private var store = SettingsStore()

  var body: some View {
    List {
      Section {
        Toggle(isOn: store.bind(Settings.ankiMode) { on in
          Settings.ankiMode = on
          Settings.ankiModeCombineReadingMeaning = false
        }) {
          SubtitleLabel("Anki mode", "Do reviews without typing answers")
        }
      } footer: {
        Text("Anki mode lets you do reviews without typing answers — reveal the answer and mark yourself right or wrong.")
      }

      if Settings.ankiMode {
        Section {
          Button { nav.openAnkiTaskType() } label: {
            DetailDisclosureRow(title: "Anki mode applies to",
                                value: Settings.ankiModeTaskType.description)
          }
          if Settings.ankiModeTaskType == .both {
            Toggle(isOn: store
              .bind(Settings.ankiModeCombineReadingMeaning) {
                Settings.ankiModeCombineReadingMeaning = $0
              }) {
                SubtitleLabel("Combine Reading + Meaning",
                              "Only one review for reading and meaning with Anki mode enabled")
              }
          }
        }
      }
    }
    .onAppear { store.refresh() }
  }
}

// MARK: - Notifications

/// Wraps the notification toggles plus the authorization flow: turning a toggle on requests
/// permission (or bounces to system Settings if denied) and only then enables the setting.
@available(iOS 15.0, *)
final class NotificationsModel: ObservableObject {
  @Published var allReviews = Settings.notificationsAllReviews
  @Published var badging = Settings.notificationsBadging
  @Published var sounds = Settings.notificationSounds

  func setAllReviews(_ on: Bool) {
    prompt(on) { Settings.notificationsAllReviews = $0
      self.allReviews = $0
    }
  }

  func setBadging(_ on: Bool) {
    prompt(on) { Settings.notificationsBadging = $0
      self.badging = $0
    }
  }

  func setSounds(_ on: Bool) {
    prompt(on) { Settings.notificationSounds = $0
      self.sounds = $0
    }
  }

  private func prompt(_ on: Bool, _ apply: @escaping (Bool) -> Void) {
    if !on {
      apply(false)
      UIApplication.shared.applicationIconBadgeNumber = 0
      return
    }
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
      switch settings.authorizationStatus {
      case .authorized, .provisional, .ephemeral:
        DispatchQueue.main.async { apply(true) }
      case .notDetermined:
        center.requestAuthorization(options: [.badge, .alert, .sound]) { granted, _ in
          DispatchQueue.main.async { apply(granted) }
        }
      case .denied:
        DispatchQueue.main.async {
          if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
          }
          apply(false)
        }
      @unknown default:
        DispatchQueue.main.async { apply(false) }
      }
    }
  }
}

@available(iOS 15.0, *)
struct NotificationsSettingsScreen: View {
  @StateObject private var model = NotificationsModel()

  var body: some View {
    List {
      Toggle("Notify for all available reviews",
             isOn: Binding(get: { model.allReviews }, set: { model.setAllReviews($0) }))
      Toggle("Badge the app icon",
             isOn: Binding(get: { model.badging }, set: { model.setBadging($0) }))
      Toggle("Play sound with notifications",
             isOn: Binding(get: { model.sounds }, set: { model.setSounds($0) }))
    }
  }
}

// MARK: - Shared rows

/// A title (and optional trailing value) with a disclosure chevron, for `Button`-based nav rows
/// inside a `List`.
@available(iOS 15.0, *)
struct DetailDisclosureRow: View {
  let title: String
  var value: String?

  var body: some View {
    HStack {
      Text(title).foregroundStyle(.primary)
      Spacer()
      if let value = value, !value.isEmpty {
        Text(value).foregroundStyle(.secondary)
      }
      Image(systemName: "chevron.right")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.tertiary)
    }
  }
}

/// A two-line label (title + grey subtitle) for toggles that carry an explanation.
@available(iOS 15.0, *)
struct SubtitleLabel: View {
  let title: String
  let subtitle: String

  init(_ title: String, _ subtitle: String) {
    self.title = title
    self.subtitle = subtitle
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
      Text(subtitle).font(.caption).foregroundStyle(.secondary)
    }
  }
}
