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

import SwiftUI
import WaniKaniAPI

// Navigation + app-level state for the SwiftUI NavigationStack architecture. Replaces the
// UINavigationController backbone and the navigation/orchestration that used to live in AppDelegate
// and the various UIHostingController subclasses.

// MARK: - Routes

/// A pushable destination in the main NavigationStack. Value-typed so it can live in a
/// `NavigationPath`.
enum AppRoute: Hashable {
  case statistics
  case search
  case subjectDetail(Int64) // subject id
  case subjectList(SubjectListSource, title: String)
  case lessonPicker
  case forecast
  case listeningPractice
  case reversePractice
  case reviewOrder
}

/// A full-screen review flow launch (reviews are modal, not pushed).
struct ReviewLaunch: Identifiable {
  let id = UUID()
  let items: [ReviewItem]
  let isPracticeSession: Bool
}

/// A full-screen lessons flow launch.
struct LessonLaunch: Identifiable {
  let id = UUID()
  let items: [ReviewItem]
}

// MARK: - Router

@available(iOS 16.0, *)
final class AppRouter: ObservableObject {
  @Published var path = NavigationPath()
  @Published var review: ReviewLaunch?
  @Published var lessons: LessonLaunch?
  @Published var settingsPresented = false
  /// Set when the API token is rejected and the user must re-authenticate.
  @Published var reauthenticate = false

  func push(_ route: AppRoute) { path.append(route) }
  func popToRoot() { path = NavigationPath() }
}

extension Notification.Name {
  /// Posted by the appearance picker when `Settings.interfaceStyle` changes.
  static let interfaceStyleChanged = Notification.Name("interfaceStyleChanged")
}

// MARK: - App state

/// Owns the shared `TKMServices`, tracks auth, and performs the login/logout/setup that used to
/// live
/// in `AppDelegate`.
@available(iOS 16.0, *)
final class AppState: ObservableObject {
  let services = TKMServices()
  @Published var loggedIn: Bool
  /// Drives `.preferredColorScheme` on the root, so the saved appearance applies at launch and
  /// stays in sync with SwiftUI's environment (an imperative window override desynced from
  /// SwiftUI's colorScheme, leaving `Color(uiColor:)` backgrounds stuck dark).
  @Published var interfaceStyle = Settings.interfaceStyle

  var colorScheme: ColorScheme? {
    switch interfaceStyle {
    case .light: return .light
    case .dark: return .dark
    default: return nil // .system -> follow the device
    }
  }

  init() {
    loggedIn = !Settings.userApiToken.isEmpty
    if loggedIn { configureClient() }
  }

  /// Builds the API client + local caching client for the current token. Mirrors the old
  /// AppDelegate.setMainViewControllerAnimated setup.
  private func configureClient() {
    services.client = WaniKaniAPIClient(apiToken: Settings.userApiToken)
    services.localCachingClient = Screenshotter.createLocalCachingClient(client: services.client,
                                                                         reachability: services
                                                                           .reachability)
    services.client.subjectLevelGetter = services.localCachingClient
  }

  func requestNotificationPermissionIfNeeded() {
    guard !Screenshotter.isActive else { return }
    UNUserNotificationCenter.current().requestAuthorization(options: [.badge, .alert,
                                                                      .sound]) { _, _ in }
  }

  /// Called after a successful first login.
  func didLogIn(clearUserData: Bool) {
    configureClient()
    requestNotificationPermissionIfNeeded()
    if clearUserData {
      services.localCachingClient.clearAllData()
      _ = services.localCachingClient.sync(quick: true, progress: Progress(totalUnitCount: -1))
    }
    loggedIn = true
  }

  /// Called after re-authenticating an expired token (data is preserved).
  func didReauthenticate() {
    services.localCachingClient?.client.updateApiToken(Settings.userApiToken)
  }

  func logOut() {
    Settings.userApiToken = ""
    Settings.userEmailAddress = ""
    services.localCachingClient?.clearAllDataAndClose()
    services.localCachingClient = nil
    loggedIn = false
  }
}

// MARK: - Dashboard launch helpers

/// Builds the review / lesson item lists for the dashboard actions. Moved out of
/// MainWaniKaniTabViewController / MainHostingController.
@available(iOS 16.0, *)
enum ReviewLauncher {
  static func reviews(_ services: TKMServices) -> [ReviewItem] {
    let assignments = services.localCachingClient.getNonExcludedAssignments()
    var items = ReviewItem.readyForReview(assignments: assignments,
                                          localCachingClient: services.localCachingClient)
    guard !items.isEmpty else { return [] }
    items = sortReviewItems(items: items, services: services)
    if Settings.reviewItemsLimitEnabled || Settings.catchUpMode,
       items.count > Settings.reviewItemsLimit {
      items = Array(items[0 ..< Int(Settings.reviewItemsLimit)])
    }
    return items
  }

  static func lessons(_ services: TKMServices) -> [ReviewItem] {
    let assignments = services.localCachingClient.getNonExcludedAssignments()
    var items = ReviewItem.readyForLessons(assignments: assignments,
                                           localCachingClient: services.localCachingClient)
      .shuffled()
    guard !items.isEmpty else { return [] }
    if !Settings.randomLessonOrder {
      items = items.sorted(by: { a, b in a.compareForLessons(other: b) })
    }
    if items.count > Settings.lessonBatchSize {
      items = Array(items[0 ..< Int(Settings.lessonBatchSize)])
    }
    return items
  }

  static func recentMistakes(_ services: TKMServices) -> [ReviewItem] {
    let a = services.localCachingClient.getAllRecentMistakeAssignments()
    return ReviewItem.readyForRecentMistakesReview(assignments: a,
                                                   localCachingClient: services.localCachingClient)
      .shuffled()
  }

  static func recentLessons(_ services: TKMServices) -> [ReviewItem] {
    let a = services.localCachingClient.getAllRecentLessonAssignments()
    return ReviewItem.readyForRecentLessonReview(assignments: a,
                                                 localCachingClient: services.localCachingClient)
      .shuffled()
  }

  static func apprenticeLeeches(_ services: TKMServices) -> [ReviewItem] {
    let a = services.localCachingClient.getAssignmentsInCategory(category: .apprentice)
    return ReviewItem.readyForAlreadyPassedApprenticeReview(assignments: a,
                                                            localCachingClient: services
                                                              .localCachingClient).shuffled()
  }

  static func allLeeches(_ services: TKMServices) -> [ReviewItem] {
    let a = services.localCachingClient.getAllLeeches()
    return ReviewItem.readyForLeechReview(assignments: a,
                                          localCachingClient: services.localCachingClient)
      .shuffled()
  }

  static func selfStudyCurrentLevel(_ services: TKMServices) -> [ReviewItem] {
    let a = services.localCachingClient.getAssignmentsAtUsersCurrentLevel()
    return ReviewItem.readyForSelfStudy(assignments: a,
                                        localCachingClient: services.localCachingClient).shuffled()
  }

  /// Vocabulary with audio, for listening practice (current level, else all).
  static func listeningSubjects(_ services: TKMServices) -> [TKMSubject] {
    let client = services.localCachingClient!
    func vocabWithAudio(_ assignments: [TKMAssignment]) -> [TKMSubject] {
      assignments.filter { $0.isReviewStage }
        .compactMap { client.getSubject(id: $0.subjectID) }
        .filter { $0.hasVocabulary && !$0.vocabulary.audio.isEmpty }
    }
    let found = vocabWithAudio(client.getAssignmentsAtUsersCurrentLevel())
    return (found.isEmpty ? vocabWithAudio(client.getAllAssignments()) : found).shuffled()
  }

  /// Kanji / vocabulary with readings, for reverse practice (current level, else all).
  static func reverseSubjects(_ services: TKMServices) -> [TKMSubject] {
    let client = services.localCachingClient!
    func recallable(_ assignments: [TKMAssignment]) -> [TKMSubject] {
      assignments.filter { $0.isReviewStage }
        .compactMap { client.getSubject(id: $0.subjectID) }
        .filter { ($0.hasKanji || $0.hasVocabulary) && !$0.readings.isEmpty }
    }
    let found = recallable(client.getAssignmentsAtUsersCurrentLevel())
    return (found.isEmpty ? recallable(client.getAllAssignments()) : found).shuffled()
  }
}
