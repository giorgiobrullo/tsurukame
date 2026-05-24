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

// MARK: - Routes + Navigator

/// A pushable settings destination. Closure-free so it can live in a `NavigationPath`; the picker
/// setters are reconstructed in `SettingsView.destination`.
enum SettingsRoute: Hashable {
  case appearance, audio, account, dashboard, anki, notifications, subjectInfo
  case lessonSettings, reviewSettings, lessonOrder
  case interfaceStyle, fontSize, fonts, offlineAudio
  case ankiTaskType, lessonBatchSize, apprenticeLimit
  case reviewItemsLimit, leechThreshold, reviewOrder, taskOrder, reviewBatchSize
}

enum SettingsAlert: Identifiable {
  case logout, imageCacheCleared, noJapaneseKeyboard
  var id: Int { hashValue }
}

/// Drives the settings `NavigationStack`. Replaces the UINavigationController-pushing navigator.
@available(iOS 16.0, *)
final class SettingsNavigator: ObservableObject {
  let services: TKMServices
  @Published var path = NavigationPath()
  @Published var alert: SettingsAlert?
  @Published var shareDatabase = false

  init(services: TKMServices) { self.services = services }

  private func push(_ route: SettingsRoute) { path.append(route) }
  func pop() { if !path.isEmpty { path.removeLast() } }

  func openAppearance() { push(.appearance) }
  func openAudio() { push(.audio) }
  func openAccount() { push(.account) }
  func openDashboard() { push(.dashboard) }
  func openAnki() { push(.anki) }
  func openNotifications() { push(.notifications) }
  func openAnkiTaskType() { push(.ankiTaskType) }
  func openLessonSettings() { push(.lessonSettings) }
  func openReviewSettings() { push(.reviewSettings) }
  func openSubjectInfoSettings() { push(.subjectInfo) }
  func openLessonOrder() { push(.lessonOrder) }
  func openLessonBatchSize() { push(.lessonBatchSize) }
  func openApprenticeLimit() { push(.apprenticeLimit) }
  func openReviewItemsLimit() { push(.reviewItemsLimit) }
  func openLeechThreshold() { push(.leechThreshold) }
  func openReviewOrder() { push(.reviewOrder) }
  func openTaskOrder() { push(.taskOrder) }
  func openReviewBatchSize() { push(.reviewBatchSize) }
  func openInterfaceStyle() { push(.interfaceStyle) }
  func openFontSize() { push(.fontSize) }
  func openFonts() { push(.fonts) }
  func openOfflineAudio() { push(.offlineAudio) }

  func showNoJapaneseKeyboardAlert() { alert = .noJapaneseKeyboard }
  func exportDatabase() { shareDatabase = true }
  func clearImageCache() {
    URLCache.shared.removeAllCachedResponses()
    alert = .imageCacheCleared
  }

  func logOut() { alert = .logout }
}

// MARK: - Settings root (nested NavigationStack)

/// The Settings screen, presented as a sheet with its own NavigationStack. Replaces
/// SettingsHostingController + the UIKit choice-list picker view controllers.
@available(iOS 16.0, *)
struct SettingsView: View {
  @StateObject private var nav: SettingsNavigator
  @Environment(\.dismiss) private var dismiss

  init(services: TKMServices) {
    _nav = StateObject(wrappedValue: SettingsNavigator(services: services))
  }

  var body: some View {
    NavigationStack(path: $nav.path) {
      SettingsHubView(nav: nav)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } }
        }
        .navigationDestination(for: SettingsRoute.self) { destination($0) }
    }
    .alert(item: $nav.alert) { which in alert(which) }
    .sheet(isPresented: $nav.shareDatabase) {
      ActivityView(items: [LocalCachingClient.databaseUrl()])
    }
  }

  @ViewBuilder
  private func destination(_ route: SettingsRoute) -> some View {
    switch route {
    case .appearance: AppearanceSettingsScreen(nav: nav).navigationTitle("Appearance")
    case .audio: AudioSettingsScreen(nav: nav).navigationTitle("Audio")
    case .account: AccountSettingsScreen(nav: nav).navigationTitle("Account")
    case .dashboard: DashboardSettingsScreen().navigationTitle("Dashboard")
    case .anki: AnkiSettingsScreen(nav: nav).navigationTitle("Anki mode")
    case .notifications: NotificationsSettingsScreen().navigationTitle("Notifications")
    case .subjectInfo: SubjectDetailsSettingsScreen().navigationTitle("Subject info")
    case .lessonSettings: LessonSettingsScreen(nav: nav).navigationTitle("Lessons")
    case .reviewSettings: ReviewSettingsScreen(nav: nav).navigationTitle("Reviews")
    case .lessonOrder: LessonOrderScreen().navigationTitle("Lesson Order")
    case .fonts: FontsScreen(model: FontsModel(services: nav.services)).navigationTitle("Fonts")
    case .offlineAudio:
      OfflineAudioScreen(model: OfflineAudioModel(services: nav.services))
        .navigationTitle("Offline audio")
    case .interfaceStyle: interfaceStylePicker
    case .fontSize: fontSizePicker
    case .ankiTaskType:
      enumPicker("Anki Mode Applies To", Settings.ankiModeTaskType,
                 Settings.$ankiModeTaskType.defaultValue) { Settings.ankiModeTaskType = $0 }
    case .reviewOrder:
      enumPicker("Review Order", Settings.reviewOrder,
                 Settings.$reviewOrder.defaultValue) { Settings.reviewOrder = $0 }
    case .lessonBatchSize: lessonBatchSizePicker
    case .apprenticeLimit: apprenticeLimitPicker
    case .reviewItemsLimit: reviewItemsLimitPicker
    case .leechThreshold: leechThresholdPicker
    case .taskOrder: taskOrderPicker
    case .reviewBatchSize: reviewBatchSizePicker
    }
  }

  private func alert(_ which: SettingsAlert) -> Alert {
    switch which {
    case .logout:
      return Alert(title: Text("Are you sure?"),
                   primaryButton: .destructive(Text("Log out")) {
                     NotificationCenter.default.post(name: .logout, object: nil)
                   },
                   secondaryButton: .cancel())
    case .imageCacheCleared:
      return Alert(title: Text("Image cache cleared"), dismissButton: .default(Text("OK")))
    case .noJapaneseKeyboard:
      return Alert(title: Text("No Japanese keyboard"),
                   message: Text("You must add a Japanese keyboard to your device.\nOpen Settings "
                     + "then General ⮕ Keyboard ⮕ Keyboards ⮕ Add New Keyboard."),
                   dismissButton: .cancel(Text("Close")))
    }
  }

  // MARK: Choice-list pickers (replacing the make*ViewController factories)

  private func choice<V: Equatable>(_ choices: [ChoiceListScreen<V>.Choice], _ current: V,
                                    _ def: V?, _ help: String?,
                                    set: @escaping (V) -> Void) -> some View {
    ChoiceListScreen(choices: choices, current: current, defaultValue: def, helpText: help,
                     onSelect: { set($0)
                       nav.pop()
                     })
  }

  private func enumPicker<T>(_ title: String, _ current: T, _ def: T,
                             set: @escaping (T) -> Void) -> some View
    where T: CaseIterable & CustomStringConvertible & Equatable {
    choice(Array(T.allCases).map { .init(label: $0.description, value: $0) }, current, def, nil,
           set: set).navigationTitle(title)
  }

  private var interfaceStylePicker: some View {
    choice(Array(InterfaceStyle.allCases).map { .init(label: $0.description, value: $0) },
           Settings.interfaceStyle, Settings.$interfaceStyle.defaultValue, nil) { style in
      Settings.interfaceStyle = style
      NotificationCenter.default.post(name: .interfaceStyleChanged, object: nil)
    }.navigationTitle("Interface Style")
  }

  private var fontSizePicker: some View {
    let choices = stride(from: 1.0, through: 2.5, by: 0.25)
      .map { ChoiceListScreen<Float>.Choice(label: "\(Int(($0 * 100).rounded()))%",
                                            value: Float($0)) }
    return choice(choices, Settings.fontSize, Settings.$fontSize.defaultValue, nil) {
      Settings.fontSize = $0
    }.navigationTitle("Font Size")
  }

  private var lessonBatchSizePicker: some View {
    var choices = [ChoiceListScreen<Int>.Choice(label: "1 lesson", value: 1)]
    choices += (2 ... 10).map { .init(label: "\($0) lessons", value: $0) }
    return choice(choices, Settings.lessonBatchSize, Settings.$lessonBatchSize.defaultValue,
                  "Set the number of new lessons to be introduced before the quiz session.") {
      Settings.lessonBatchSize = $0
    }.navigationTitle("Lesson Batch Size")
  }

  private var apprenticeLimitPicker: some View {
    var choices = [ChoiceListScreen<Int>.Choice(label: "No limit", value: Int.max)]
    choices += stride(from: 25, through: 200, by: 25).map { .init(label: "\($0)", value: $0) }
    return choice(choices, Settings.apprenticeLessonsLimit,
                  Settings.$apprenticeLessonsLimit.defaultValue,
                  "Stop yourself from starting new lessons if you have more than this number of "
                    + "Apprentice-level items already.") {
      Settings.apprenticeLessonsLimit = $0
    }.navigationTitle("Apprentice Lessons Limit")
  }

  private var reviewItemsLimitPicker: some View {
    let choices = [5, 10, 15, 20, 25, 30, 50, 75, 100]
      .map { ChoiceListScreen<Int>.Choice(label: "\($0) reviews", value: $0) }
    return choice(choices, Settings.reviewItemsLimit, Settings.$reviewItemsLimit.defaultValue,
                  "Set the number of items to review in a session.") {
      Settings.reviewItemsLimit = $0
    }.navigationTitle("Review Batch Size")
  }

  private var leechThresholdPicker: some View {
    let choices = stride(from: 1.0, through: 5.0, by: 0.25)
      .map { ChoiceListScreen<Float>.Choice(label: "\($0)", value: Float($0)) }
    return choice(choices, Settings.leechThreshold, Settings.$leechThreshold.defaultValue,
                  "Leeches are the items that you regularly get wrong. The lower the leech "
                    + "threshold value, the more items will be considered leeches.") {
      Settings.leechThreshold = $0
    }.navigationTitle("Leech Threshold")
  }

  private var taskOrderPicker: some View {
    let choices = [ChoiceListScreen<Bool>.Choice(label: "Meaning then Reading", value: true),
                   ChoiceListScreen<Bool>.Choice(label: "Reading then Meaning", value: false)]
    return choice(choices, Settings.meaningFirst, Settings.$meaningFirst.defaultValue, nil) {
      Settings.meaningFirst = $0
    }.navigationTitle("Back-to-back Order")
  }

  private var reviewBatchSizePicker: some View {
    let name = "Reviews Between Meaning & Reading"
    let choices = (3 ... 10).map { ChoiceListScreen<Int>.Choice(label: "\($0) reviews", value: $0) }
    return choice(choices, Settings.reviewBatchSize, Settings.$reviewBatchSize.defaultValue,
                  "Only used when back-to-back reviews are disabled: how many other items you can "
                    + "encounter between the reading and meaning of a given item.") {
      Settings.reviewBatchSize = $0
    }.navigationTitle(name)
  }
}

/// UIActivityViewController wrapper for the "export database" share sheet.
@available(iOS 16.0, *)
struct ActivityView: UIViewControllerRepresentable {
  let items: [Any]
  func makeUIViewController(context _: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: items, applicationActivities: nil)
  }

  func updateUIViewController(_: UIActivityViewController, context _: Context) {}
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
