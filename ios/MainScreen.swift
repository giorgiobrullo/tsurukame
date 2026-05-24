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
    ZStack(alignment: .leading) {
      LinearGradient(colors: TKMStyle.radicalGradient.map { Color(cgColor: $0) },
                     startPoint: .top, endPoint: .bottom)
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
        Spacer()
        if model.user?.onVacation == true {
          Image(systemName: "beach.umbrella.fill").foregroundStyle(.white)
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
    }
    .frame(height: 76)
  }
}

@available(iOS 15.0, *)
final class MainHostingController: UIHostingController<MainScreen>, TKMViewController,
  SearchResultViewControllerDelegate, LoginViewControllerDelegate {
  private let services: TKMServices
  private let model: MainModel
  private let authNd = NotificationDispatcher()
  private var searchController: UISearchController!
  private var isShowingUnauthorizedAlert = false

  var canSwipeToGoBack: Bool { false }

  init(services: TKMServices) {
    self.services = services
    let model = MainModel(services: services)
    self.model = model
    super.init(rootView: MainScreen(model: model))
    title = "Tsurukame"
    model.dashboardModel.actions = makeDashboardActions()

    let results = SubjectSearchResultsController(services: services, delegate: self)
    searchController = UISearchController(searchResultsController: results)
    searchController.searchResultsUpdater = results
    searchController.searchBar.autocapitalizationType = .none
    searchController.hidesNavigationBarDuringPresentation = false
    navigationItem.searchController = searchController
    navigationItem.hidesSearchBarWhenScrolling = false
    navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "gearshape"),
                                                        style: .plain, target: self,
                                                        action: #selector(openSettings))

    authNd.add(name: .lccUnauthorized) { [weak self] _ in self?.clientIsUnauthorized() }
    authNd.add(name: .lccHibernating) { [weak self] _ in self?.clientIsHibernating() }
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    model.start()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.isNavigationBarHidden = false
  }

  func refresh(quick: Bool) { model.refresh(quick: quick) }

  @objc private func openSettings() {
    navigationController?.pushViewController(SettingsHostingController(services: services),
                                             animated: true)
  }

  // MARK: - Dashboard actions (moved from MainWaniKaniTabViewController)

  private func makeDashboardActions() -> DashboardActions {
    var a = DashboardActions()
    a.startLessons = { [weak self] in self?.startLessons() }
    a.startReviews = { [weak self] in self?.startReviews() }
    a.showLessonPicker = { [weak self] in self?.showLessonPicker() }
    a.showReviewOrder = { [weak self] in
      self?.navigationController?.pushViewController(makeReviewOrderViewController(),
                                                     animated: true)
    }
    a.openForecast = { [weak self] in self?.showForecast() }
    a.selfStudy = { [weak self] in self?.startSelfStudyCurrentLevel() }
    a.listening = { [weak self] in self?.pushPractice(ListeningPracticeViewController()) }
    a.reverse = { [weak self] in self?.pushPractice(ReversePracticeViewController()) }
    a.recentLessons = { [weak self] in self?.startRecentLessonReviews() }
    a.recentMistakes = { [weak self] in self?.startRecentMistakeReviews() }
    a.apprenticeLeeches = { [weak self] in self?.startAlreadyPassedApprenticeReviews() }
    a.allLeeches = { [weak self] in self?.startAllLeechReviews() }
    a.openStatistics = { [weak self] in
      guard let self = self else { return }
      let vc = StatsViewController()
      vc.setup(services: self.services)
      self.navigationController?.pushViewController(vc, animated: true)
    }
    a.showAllCurrentLevel = { [weak self] in
      guard let self = self,
            let level = self.services.localCachingClient.getUserInfo()
            .map({ Int($0.currentLevel) }) else { return }
      self.navigationController?
        .pushViewController(SubjectListHostingController(services: self.services,
                                                         title: "Level \(level)",
                                                         source: .level(level)),
                            animated: true)
    }
    return a
  }

  private func pushReview(items: [ReviewItem], isPracticeSession: Bool) {
    guard !items.isEmpty else { return }
    navigationController?.pushViewController(SwiftUIReviewHostingController(services: services,
                                                                            items: items,
                                                                            isPracticeSession: isPracticeSession),
                                             animated: true)
  }

  private func pushPractice(_ vc: ListeningPracticeViewController) {
    vc.setup(services: services)
    navigationController?.pushViewController(vc, animated: true)
  }

  private func pushPractice(_ vc: ReversePracticeViewController) {
    vc.setup(services: services)
    navigationController?.pushViewController(vc, animated: true)
  }

  func startReviews() {
    let assignments = services.localCachingClient.getNonExcludedAssignments()
    var items = ReviewItem.readyForReview(assignments: assignments,
                                          localCachingClient: services.localCachingClient)
    guard !items.isEmpty else { return }
    items = sortReviewItems(items: items, services: services)
    if Settings.reviewItemsLimitEnabled || Settings.catchUpMode,
       items.count > Settings.reviewItemsLimit {
      items = Array(items[0 ..< Int(Settings.reviewItemsLimit)])
    }
    pushReview(items: items, isPracticeSession: false)
  }

  func startLessons() {
    let assignments = services.localCachingClient.getNonExcludedAssignments()
    var items = ReviewItem.readyForLessons(assignments: assignments,
                                           localCachingClient: services.localCachingClient)
      .shuffled()
    guard !items.isEmpty else { return }
    if !Settings.randomLessonOrder {
      items = items.sorted(by: { a, b in a.compareForLessons(other: b) })
    }
    if items.count > Settings.lessonBatchSize {
      items = Array(items[0 ..< Int(Settings.lessonBatchSize)])
    }
    navigationController?.pushViewController(LessonsHostingController(services: services,
                                                                      items: items),
                                             animated: true)
  }

  func showLessonPicker() {
    navigationController?.pushViewController(LessonPickerHostingController(services: services),
                                             animated: true)
  }

  func showForecast() {
    let rows = UpcomingReviewsScreen.rows(services: services)
    navigationController?.pushViewController(TKMHostingController(title: "Upcoming reviews",
                                                                  rootView: UpcomingReviewsScreen(rows: rows)),
                                             animated: true)
  }

  func startRecentMistakeReviews() {
    let a = services.localCachingClient.getAllRecentMistakeAssignments()
    pushReview(items: ReviewItem.readyForRecentMistakesReview(assignments: a,
                                                              localCachingClient: services
                                                                .localCachingClient).shuffled(),
               isPracticeSession: true)
  }

  func startRecentLessonReviews() {
    let a = services.localCachingClient.getAllRecentLessonAssignments()
    pushReview(items: ReviewItem.readyForRecentLessonReview(assignments: a,
                                                            localCachingClient: services
                                                              .localCachingClient).shuffled(),
               isPracticeSession: true)
  }

  func startAlreadyPassedApprenticeReviews() {
    let a = services.localCachingClient.getAssignmentsInCategory(category: .apprentice)
    pushReview(items: ReviewItem.readyForAlreadyPassedApprenticeReview(assignments: a,
                                                                       localCachingClient: services
                                                                         .localCachingClient)
        .shuffled(), isPracticeSession: true)
  }

  func startAllLeechReviews() {
    let a = services.localCachingClient.getAllLeeches()
    pushReview(items: ReviewItem.readyForLeechReview(assignments: a,
                                                     localCachingClient: services
                                                       .localCachingClient).shuffled(),
               isPracticeSession: true)
  }

  func startSelfStudyCurrentLevel() {
    let a = services.localCachingClient.getAssignmentsAtUsersCurrentLevel()
    pushReview(items: ReviewItem.readyForSelfStudy(assignments: a,
                                                   localCachingClient: services
                                                     .localCachingClient).shuffled(),
               isPracticeSession: true)
  }

  // MARK: - SearchResultViewControllerDelegate

  func searchResultSelected(subject: TKMSubject) {
    searchController.dismiss(animated: true) { [weak self] in
      guard let self = self else { return }
      self.navigationController?
        .pushViewController(SubjectDetailHostingController(services: self.services,
                                                           subject: subject),
                            animated: true)
    }
  }

  // MARK: - Auth

  private func clientIsUnauthorized() {
    if isShowingUnauthorizedAlert { return }
    isShowingUnauthorizedAlert = true
    let ac = UIAlertController(title: "Logged out",
                               message: "Your API token expired, is invalid, or lacks the required permissions. Please log in again — you won't lose review progress.",
                               preferredStyle: .alert)
    ac
      .addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
        self?.loginAgain()
      })
    present(ac, animated: true)
  }

  private func clientIsHibernating() {
    if isShowingUnauthorizedAlert { return }
    isShowingUnauthorizedAlert = true
    present(CommonErrors.getHibernatingAccountAlertController(), animated: true)
  }

  private func loginAgain() {
    guard services.localCachingClient.getUserInfo() != nil else { return }
    let vc = LoginHostingController()
    vc.delegate = self
    vc.forcedEmail = Settings.userEmailAddress.isEmpty ? nil : Settings.userEmailAddress
    navigationController?.pushViewController(vc, animated: true)
  }

  // MARK: - LoginViewControllerDelegate

  func loginComplete() {
    services.localCachingClient.client.updateApiToken(Settings.userApiToken)
    navigationController?.popViewController(animated: true)
    isShowingUnauthorizedAlert = false
  }
}
