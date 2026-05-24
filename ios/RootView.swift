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
import UIKit
import WaniKaniAPI

// The SwiftUI NavigationStack root. Replaces the UINavigationController backbone and the
// AppDelegate-driven bootstrap. Dashboard-reachable screens are value-typed routes pushed onto the
// stack; the review / lessons / settings / login flows are presented modally, reusing their proven
// hosting controllers inside a contained UINavigationController.

@available(iOS 16.0, *)
struct RootView: View {
  @ObservedObject var state: AppState
  @StateObject private var router = AppRouter()
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    Group {
      if state.loggedIn {
        MainContainer(state: state, router: router)
      } else {
        LoginContainer(onComplete: { state.didLogIn(clearUserData: true) })
          .ignoresSafeArea()
      }
    }
    .onChange(of: scenePhase) { phase in
      switch phase {
      case .active:
        state.services.reachability.startNotifier()
      case .background:
        state.services.reachability.stopNotifier()
        if state.loggedIn {
          NotificationScheduler.update(services: state.services)
          BackgroundSync.schedule()
        }
      default:
        break
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .logout)) { _ in
      router.settingsPresented = false
      state.logOut()
    }
    .onOpenURL { _ = handleApplink($0) }
    .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
      if let url = activity.webpageURL { _ = handleApplink(url) }
    }
    .onContinueUserActivity(SiriShortcutHelper.ShortcutType.reviews.rawValue) { _ in
      launchReviews()
    }
    .onContinueUserActivity(SiriShortcutHelper.ShortcutType.lessons.rawValue) { _ in
      launchLessons()
    }
    .fullScreenCover(isPresented: $router.reauthenticate) {
      LoginContainer(forcedEmail: Settings.userEmailAddress.isEmpty ? nil
        : Settings.userEmailAddress) {
          state.didReauthenticate()
          router.reauthenticate = false
        }
        .ignoresSafeArea()
    }
  }

  private func launchReviews() {
    let items = ReviewLauncher.reviews(state.services)
    if !items.isEmpty { router.review = ReviewLaunch(items: items, isPracticeSession: false) }
  }

  private func launchLessons() {
    let items = ReviewLauncher.lessons(state.services)
    if !items.isEmpty { router.lessons = LessonLaunch(items: items) }
  }

  /// Handles universal links and custom URL schemes by path (ignores scheme/host), mirroring the
  /// old AppDelegate.handleApplink.
  private func handleApplink(_ url: URL) -> Bool {
    let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.path ?? ""
    let components = path.split(separator: "/")
    guard !components.isEmpty else { return true }
    guard state.loggedIn else { return false }
    let client = state.services.localCachingClient

    switch components[0] {
    case "reviews": launchReviews()
    case "lessons": launchLessons()
    case "subject":
      if components.count > 1, let id = Int64(components[1]) { router.push(.subjectDetail(id)) }
    case "radical":
      if components.count > 1,
         let s = client?.getSubject(japanese: String(components[1]), type: .radical) {
        router.push(.subjectDetail(s.id))
      }
    case "kanji":
      if components.count > 1,
         let s = client?.getSubject(japanese: String(components[1]), type: .kanji) {
        router.push(.subjectDetail(s.id))
      }
    case "vocabulary":
      if components.count > 1,
         let s = client?.getSubject(japanese: String(components[1]), type: .vocabulary) {
        router.push(.subjectDetail(s.id))
      }
    default:
      return false
    }
    return true
  }
}

// MARK: - Logged-in container

@available(iOS 16.0, *)
private struct MainContainer: View {
  @ObservedObject var state: AppState
  @ObservedObject var router: AppRouter
  @StateObject private var model: MainModel
  @StateObject private var searcher = Searcher()
  @State private var searchText = ""

  init(state: AppState, router: AppRouter) {
    self.state = state
    self.router = router
    _model = StateObject(wrappedValue: MainModel(services: state.services))
  }

  var body: some View {
    NavigationStack(path: $router.path) {
      Group {
        if searchText.isEmpty {
          MainScreen(model: model)
        } else {
          SubjectSearchScreen(model: searcher.results) { router.push(.subjectDetail($0.id)) }
        }
      }
      .navigationTitle("Tsurukame")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button { router.settingsPresented = true } label: { Image(systemName: "gearshape") }
        }
      }
      .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                  prompt: "Search subjects")
      .onChange(of: searchText) { searcher.update(query: $0, services: state.services) }
      .navigationDestination(for: AppRoute.self) { route in destination(for: route) }
    }
    .onAppear {
      model.dashboardModel.actions = makeActions()
      model.start()
    }
    .onReceive(NotificationCenter.default.publisher(for: .lccUnauthorized)) { _ in
      router.reauthenticate = true
    }
    .fullScreenCover(item: $router.review) { launch in
      ContainedNav {
        let vc = SwiftUIReviewHostingController(services: state.services, items: launch.items,
                                                isPracticeSession: launch.isPracticeSession)
        vc.onClose = { router.review = nil }
        return vc
      }
      .ignoresSafeArea()
    }
    .fullScreenCover(item: $router.lessons) { launch in
      ContainedNav {
        let vc = LessonsHostingController(services: state.services, items: launch.items)
        vc.onClose = { router.lessons = nil }
        return vc
      }
      .ignoresSafeArea()
    }
    .sheet(isPresented: $router.settingsPresented) {
      SettingsView(services: state.services)
    }
  }

  // MARK: Route destinations

  @ViewBuilder
  private func destination(for route: AppRoute) -> some View {
    switch route {
    case .statistics:
      StatsView(data: StatsViewController.makeData(services: state.services))
        .navigationTitle("Statistics")
    case let .subjectDetail(id):
      SubjectDetailRoute(services: state.services, router: router, subjectID: id)
    case let .subjectList(source, title):
      SubjectListScreen(sections: SubjectListBuilder.sections(services: state.services,
                                                              source: source)) {
        router.push(.subjectDetail($0.id))
      }
      .navigationTitle(title)
    case .lessonPicker:
      LessonPickerRoute(services: state.services, router: router)
    case .forecast:
      UpcomingReviewsScreen(rows: UpcomingReviewsScreen.rows(services: state.services))
        .navigationTitle("Upcoming reviews")
    case .listeningPractice:
      ListeningPracticeScreen(services: state.services,
                              subjects: ReviewLauncher.listeningSubjects(state.services))
        .navigationTitle("Listening")
    case .reversePractice:
      ReversePracticeScreen(services: state.services,
                            subjects: ReviewLauncher.reverseSubjects(state.services))
        .navigationTitle("Reverse")
    case .reviewOrder:
      ChoiceListScreen(choices: Array(ReviewOrder.allCases)
        .map { .init(label: $0.description, value: $0) },
        current: Settings.reviewOrder,
        defaultValue: Settings.$reviewOrder.defaultValue,
        helpText: nil,
        onSelect: { Settings.reviewOrder = $0
          if !router.path.isEmpty { router.path.removeLast() }
        })
        .navigationTitle("Review order")
        .navigationBarTitleDisplayMode(.inline)
    }
  }

  // MARK: Dashboard actions

  private func makeActions() -> DashboardActions {
    var a = DashboardActions()
    func launch(_ items: [ReviewItem], practice: Bool) {
      if !items.isEmpty { router.review = ReviewLaunch(items: items, isPracticeSession: practice) }
    }
    a.startLessons = {
      let items = ReviewLauncher.lessons(state.services)
      if !items.isEmpty { router.lessons = LessonLaunch(items: items) }
    }
    a.startReviews = { launch(ReviewLauncher.reviews(state.services), practice: false) }
    a.showLessonPicker = { router.push(.lessonPicker) }
    a.showReviewOrder = { router.push(.reviewOrder) }
    a.openForecast = { router.push(.forecast) }
    a.selfStudy = { launch(ReviewLauncher.selfStudyCurrentLevel(state.services), practice: true) }
    a.listening = { router.push(.listeningPractice) }
    a.reverse = { router.push(.reversePractice) }
    a.recentLessons = { launch(ReviewLauncher.recentLessons(state.services), practice: true) }
    a.recentMistakes = { launch(ReviewLauncher.recentMistakes(state.services), practice: true) }
    a
      .apprenticeLeeches = {
        launch(ReviewLauncher.apprenticeLeeches(state.services), practice: true)
      }
    a.allLeeches = { launch(ReviewLauncher.allLeeches(state.services), practice: true) }
    a.openStatistics = { router.push(.statistics) }
    a.showAllCurrentLevel = {
      guard let level = state.services.localCachingClient.getUserInfo()
        .map({ Int($0.currentLevel) }) else { return }
      router.push(.subjectList(.level(level), title: "Level \(level)"))
    }
    return a
  }
}

// MARK: - Route wrapper views

/// Holds the SubjectDelegate so it isn't deallocated (SubjectDetailModel keeps it weak).
@available(iOS 16.0, *)
private struct SubjectDetailRoute: View {
  let services: TKMServices
  @StateObject private var holder: SubjectDelegateHolder
  private let subject: TKMSubject?

  init(services: TKMServices, router: AppRouter, subjectID: Int64) {
    self.services = services
    subject = services.localCachingClient.getSubject(id: subjectID)
    _holder = StateObject(wrappedValue: SubjectDelegateHolder(router: router))
  }

  var body: some View {
    Group {
      if let subject = subject {
        SubjectDetailContent(services: services, subject: subject,
                             studyMaterials: services.localCachingClient
                               .getStudyMaterial(subjectId: subject.id),
                             assignment: services.localCachingClient
                               .getAssignment(subjectId: subject.id),
                             task: nil, delegate: holder.delegate)
          .navigationTitle(subject.japanese)
          .navigationBarTitleDisplayMode(.inline)
      } else {
        Text("Subject not found")
      }
    }
  }
}

@available(iOS 16.0, *)
private final class SubjectDelegateHolder: ObservableObject {
  let delegate: RouterSubjectDelegate
  init(router: AppRouter) { delegate = RouterSubjectDelegate(router: router) }
}

@available(iOS 16.0, *)
final class RouterSubjectDelegate: NSObject, SubjectDelegate {
  private let router: AppRouter
  init(router: AppRouter) { self.router = router }
  func didTapSubject(_ subject: TKMSubject) { router.push(.subjectDetail(subject.id)) }
}

@available(iOS 16.0, *)
private struct LessonPickerRoute: View {
  let router: AppRouter
  @StateObject private var model: LessonPickerModel

  init(services: TKMServices, router: AppRouter) {
    self.router = router
    _model = StateObject(wrappedValue: LessonPickerModel(services: services))
  }

  var body: some View {
    LessonPickerScreen(model: model, onBegin: {
      let items = model.selectedItems
      if !items.isEmpty { router.lessons = LessonLaunch(items: items) }
    })
    .navigationTitle("Lesson Picker")
    .navigationBarTitleDisplayMode(.inline)
  }
}

// MARK: - Search

@available(iOS 16.0, *)
private final class Searcher: ObservableObject {
  let results = SearchResultsModel()
  private var allSubjects: [TKMSubject]?

  func update(query: String, services: TKMServices) {
    if allSubjects == nil { allSubjects = services.localCachingClient?.getAllSubjects() }
    results.results = searchSubjects(query: query, in: allSubjects ?? [])
  }
}

// MARK: - UIKit bridges for the modal / login flows

/// Wraps a view controller in a fresh UINavigationController for modal presentation, so the reused
/// review / lessons / settings / login controllers keep their internal push/pop navigation.
@available(iOS 16.0, *)
struct ContainedNav: UIViewControllerRepresentable {
  let make: () -> UIViewController
  func makeUIViewController(context _: Context) -> UINavigationController {
    UINavigationController(rootViewController: make())
  }

  func updateUIViewController(_: UINavigationController, context _: Context) {}
}

/// Wraps a self-contained view controller (no internal navigation) for a NavigationStack route.
@available(iOS 16.0, *)
private struct PlainVC: UIViewControllerRepresentable {
  let make: () -> UIViewController
  func makeUIViewController(context _: Context) -> UIViewController { make() }
  func updateUIViewController(_: UIViewController, context _: Context) {}
}

/// The login screen, hosted in its own UINavigationController. Used as the logged-out root and the
/// re-authentication cover.
@available(iOS 16.0, *)
struct LoginContainer: UIViewControllerRepresentable {
  var forcedEmail: String?
  let onComplete: () -> Void

  func makeCoordinator() -> Coordinator { Coordinator(onComplete: onComplete) }

  func makeUIViewController(context: Context) -> UINavigationController {
    let vc = LoginHostingController()
    vc.forcedEmail = forcedEmail
    vc.delegate = context.coordinator
    return UINavigationController(rootViewController: vc)
  }

  func updateUIViewController(_: UINavigationController, context _: Context) {}

  final class Coordinator: NSObject, LoginViewControllerDelegate {
    let onComplete: () -> Void
    init(onComplete: @escaping () -> Void) { self.onComplete = onComplete }
    func loginComplete() { onComplete() }
  }
}
