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
import WaniKaniAPI

private func setTableViewCellCount(_ item: BasicModelItem, count: Int,
                                   disabledMessage: String? = nil) -> Bool {
  item.subtitle = count < 0 ? "-" : "\(count)"
  item.isEnabled = count > 0 && (disabledMessage == nil)

  if let message = disabledMessage {
    item.title = "\(item.title!) (\(message))"
  }

  return item.isEnabled
}

class MainWaniKaniTabViewController: UITableViewController {
  protocol Delegate: AnyObject {
    func didPullToRefresh()
  }

  var services: TKMServices!
  weak var delegate: Delegate?

  var selectedSubjectCatalogLevel = -1
  var selectedSrsStageCategory = SRSStageCategory.apprentice

  var hasLessons = false
  var hasReviews = false

  // Diffable data source so dashboard updates apply in place (only the rows whose content actually
  // changed are refreshed) instead of a full reloadData, which used to interrupt scrolling during a
  // sync. Each item's `diffIdentifier` encodes its content, so unchanged rows are left untouched.
  private var dataSource: DashboardDataSource!
  private var itemsByID = [String: any TableModelItem]()
  private var hasLoadedOnce = false

  // SwiftUI dashboard (the native rewrite). When `Settings.useSwiftUIDashboard` is on we host a
  // `DashboardScreen` over the (disabled) table instead of building table rows. `dashboardModelBox`
  // is the `DashboardModel` kept as AnyObject so it can be stored without an availability
  // attribute.
  private var dashboardHostVC: UIViewController?
  private var dashboardModelBox: AnyObject?
  private var usingSwiftUIDashboard = false

  func setup(services: TKMServices, delegate: Delegate?) {
    self.services = services
    self.delegate = delegate
  }

  override func viewDidLoad() {
    // The home screen is the SwiftUI dashboard. (The classic TableModel dashboard below is retained
    // for now but no longer installed; it'll be removed once the SwiftUI dashboard fully settles.)
    usingSwiftUIDashboard = true
    installSwiftUIDashboard()
  }

  func update() {
    if usingSwiftUIDashboard, #available(iOS 15.0, *) {
      refreshDashboardData()
    } else {
      recreateTableModel()
    }
  }

  // MARK: - SwiftUI dashboard (native rewrite)

  @available(iOS 15.0, *)
  private func installSwiftUIDashboard() {
    let model = DashboardModel()
    model.actions = makeDashboardActions()
    dashboardModelBox = model

    let host = UIHostingController(rootView: DashboardScreen(model: model,
                                                             onRefresh: { [weak self] in
                                                               self?.delegate?.didPullToRefresh()
                                                             }))
    host.view.backgroundColor = .clear
    addChild(host)
    host.view.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(host.view)
    NSLayoutConstraint.activate([
      host.view.topAnchor.constraint(equalTo: tableView.frameLayoutGuide.topAnchor),
      host.view.bottomAnchor.constraint(equalTo: tableView.frameLayoutGuide.bottomAnchor),
      host.view.leadingAnchor.constraint(equalTo: tableView.frameLayoutGuide.leadingAnchor),
      host.view.trailingAnchor.constraint(equalTo: tableView.frameLayoutGuide.trailingAnchor),
    ])
    host.didMove(toParent: self)
    dashboardHostVC = host

    tableView.isScrollEnabled = false
    tableView.separatorStyle = .none
    tableView.backgroundColor = TKMStyle.Color.background
    refreshDashboardData()
  }

  @available(iOS 15.0, *)
  private func refreshDashboardData() {
    let data = DashboardData.make(from: services)
    hasLessons = data?.lessonsEnabled ?? false
    hasReviews = data?.reviewsEnabled ?? false
    (dashboardModelBox as? DashboardModel)?.data = data
  }

  @available(iOS 15.0, *)
  private func makeDashboardActions() -> DashboardActions {
    var a = DashboardActions()
    a.startLessons = { [weak self] in if self?.hasLessons == true { self?.startLessons() } }
    a.startReviews = { [weak self] in if self?.hasReviews == true { self?.startReviews() } }
    a.showLessonPicker = { [weak self] in self?.showLessonPicker() }
    a.showReviewOrder = { [weak self] in
      guard let self = self else { return }
      self.navigationController?.pushViewController(makeReviewOrderViewController(), animated: true)
    }
    a.openForecast = { [weak self] in
      guard let self = self else { return }
      let rows = UpcomingReviewsScreen.rows(services: self.services)
      let vc = TKMHostingController(title: "Upcoming reviews",
                                    rootView: UpcomingReviewsScreen(rows: rows))
      self.navigationController?.pushViewController(vc, animated: true)
    }
    a.selfStudy = { [weak self] in self?.startSelfStudyCurrentLevel() }
    a.listening = { [weak self] in self?.startListeningPractice() }
    a.reverse = { [weak self] in self?.startReversePractice() }
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
            let level = self.services.localCachingClient.getUserInfo().map({ Int($0.currentLevel) })
      else { return }
      let vc = SubjectListHostingController(services: self.services, title: "Level \(level)",
                                            source: .level(level))
      self.navigationController?.pushViewController(vc, animated: true)
    }
    return a
  }

  // MARK: - Diffable data source

  private func configureDataSource() {
    dataSource = DashboardDataSource(tableView: tableView) { [weak self] _, _, itemID in
      guard let self = self, let item = self.itemsByID[itemID] else { return UITableViewCell() }
      return self.makeCell(for: item)
    }
    tableView.delegate = self
  }

  // Builds (or reuses) the cell for an item. Mirrors TableModel's cell construction so the existing
  // item/cell classes work unchanged.
  private func makeCell(for item: any TableModelItem) -> UITableViewCell {
    let reuseId = item.cellReuseIdentifier
    var cell = tableView.dequeueReusableCell(withIdentifier: reuseId) as? TableModelCell
    if cell == nil {
      switch item.cellFactory {
      case let .fromInterfaceBuilder(nibName):
        tableView.register(UINib(nibName: nibName, bundle: nil), forCellReuseIdentifier: reuseId)
        cell = tableView.dequeueReusableCell(withIdentifier: reuseId) as? TableModelCell
      case let .fromFunction(function):
        cell = function()
      case let .fromDefaultConstructor(cellClass):
        cell = cellClass.init(style: .default, reuseIdentifier: reuseId) as? TableModelCell
      }
    }
    guard let cell = cell else {
      fatalError("Item class \(reuseId)'s cellFactory returned nil")
    }
    CATransaction.begin()
    CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)
    cell.baseItem = item
    cell.tableView = tableView
    cell.update()
    CATransaction.commit()
    return cell
  }

  // Converts the built section/item structure into a diffable snapshot. Section and item ids are
  // de-duplicated so identical-looking rows (e.g. two "Show all" rows) stay distinct.
  private func applySnapshot(from model: TableModel) {
    var snapshot = NSDiffableDataSourceSnapshot<String, String>()
    var newItemsByID = [String: any TableModelItem]()
    var sectionTitles = [String: String]()
    var usedSectionIDs = Set<String>()
    var usedItemIDs = Set<String>()

    for (index, section) in model.sections.enumerated() where !section.hidden {
      var sid = section.headerTitle ?? "section-\(index)"
      while usedSectionIDs.contains(sid) { sid += "·" }
      usedSectionIDs.insert(sid)
      if let title = section.headerTitle { sectionTitles[sid] = title }
      snapshot.appendSections([sid])

      var itemIDs = [String]()
      for item in section.items {
        var iid = item.diffIdentifier
        while usedItemIDs.contains(iid) { iid += "#" }
        usedItemIDs.insert(iid)
        // Reuse the previous instance for unchanged ids. Diffable doesn't re-provide cells whose id
        // is unchanged, so such a cell keeps its (weak) baseItem pointing at the old instance; if
        // we
        // dropped that instance the weak ref would become nil and tapping the row would crash. Same
        // id == same content, so reusing the old instance is safe.
        newItemsByID[iid] = itemsByID[iid] ?? item
        itemIDs.append(iid)
      }
      snapshot.appendItems(itemIDs, toSection: sid)
    }

    itemsByID = newItemsByID
    dataSource.sectionTitles = sectionTitles
    dataSource.apply(snapshot, animatingDifferences: hasLoadedOnce)
    hasLoadedOnce = true
  }

  // MARK: - UITableViewDelegate

  override func tableView(_ tableView: UITableView,
                          heightForRowAt indexPath: IndexPath) -> CGFloat {
    guard let id = dataSource.itemIdentifier(for: indexPath), let item = itemsByID[id] else {
      return tableView.rowHeight
    }
    return item.rowHeight ?? tableView.rowHeight
  }

  override func tableView(_ tableView: UITableView,
                          heightForHeaderInSection section: Int) -> CGFloat {
    let title = dataSource.tableView(tableView, titleForHeaderInSection: section)
    return (title ?? "").isEmpty ? 12 : UITableView.automaticDimension
  }

  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    (tableView.cellForRow(at: indexPath) as? TableModelCell)?.didSelect()
  }

  private func recreateTableModel() {
    guard let user = services.localCachingClient.getUserInfo() else { return }

    // make sure that the selected subject level is reset each time table is loaded in case things
    // change
    selectedSubjectCatalogLevel = -1
    selectedSrsStageCategory = SRSStageCategory.apprentice

    let lessons = services.localCachingClient.availableLessonCount
    let reviews = services.localCachingClient.availableReviewCount
    let recentMistakes = services.localCachingClient.getRecentMistakesCount()
    let recentLessonCount = services.localCachingClient.recentLessonCount
    let leechCount = services.localCachingClient.leechCount
    let upcomingReviews = services.localCachingClient.upcomingReviews
    let currentLevelAssignments = services.localCachingClient.getAssignmentsAtUsersCurrentLevel()

    // Build the structure detached (we apply it via the diffable data source, not as the table's
    // own data source).
    let model = MutableTableModel(tableView: tableView, delegate: nil, attachToTableView: false)

    if !user.hasVacationStartedAt {
      let apprenticeCount = services.localCachingClient.apprenticeCount
      let limit = Settings.apprenticeLessonsLimit
      let lessonsAtLimit = apprenticeCount >= limit
      hasLessons = lessons > 0 && !lessonsAtLimit
      hasReviews = reviews > 0

      // Big gradient action cards for the two primary actions.
      model.add(section: nil)
      let lessonsSubtitle = lessonsAtLimit ? "Apprentice limit reached"
        : (lessons == 1 ? "lesson to learn" : "lessons to learn")

      // Catch-up mode: when behind, show a manageable batch ("Do N · of T waiting") instead of the
      // discouraging full total.
      let catchUpBatch = Int(Settings.reviewItemsLimit)
      let catchingUp = Settings.catchUpMode && reviews > catchUpBatch
      let reviewCardCount = catchingUp ? catchUpBatch : reviews
      let reviewsSubtitle = catchingUp ? "of \(reviews) waiting"
        : (reviews == 1 ? "review to do" : "reviews to do")
      model.add(DashboardActionCardsItem(lessonCount: lessons, reviewCount: reviewCardCount,
                                         lessonsEnabled: hasLessons, reviewsEnabled: hasReviews,
                                         lessonsSubtitle: lessonsSubtitle,
                                         reviewsSubtitle: reviewsSubtitle,
                                         onLessons: { [unowned self] in
                                           if self.hasLessons { self.startLessons() }
                                         },
                                         onReviews: { [unowned self] in
                                           if self.hasReviews { self.startReviews() }
                                         }))

      if lessons > 0 && apprenticeCount < limit {
        model.add(BasicModelItem(style: .value1,
                                 title: "Lesson Picker",
                                 subtitle: "",
                                 accessoryType: .disclosureIndicator) { [unowned self] in
            self.showLessonPicker()
          })
      }

      // Quick access to the review order without going into Settings (#340).
      if reviews > 0 {
        model.add(BasicModelItem(style: .value1,
                                 title: "Review order",
                                 subtitle: Settings.reviewOrder.description,
                                 accessoryType: .disclosureIndicator) { [unowned self] in
            self.navigationController?.pushViewController(makeReviewOrderViewController(),
                                                          animated: true)
          })
      }

      // Self-study: practice this level's items any time, no SRS penalty.
      let selfStudyCount = currentLevelAssignments.filter { $0.isReviewStage }.count
      if selfStudyCount > 0 {
        model.add(section: "Practice")
        let selfStudyItem = BasicModelItem(style: .value1, title: "Self-study current level",
                                           subtitle: "\(selfStudyCount)",
                                           accessoryType: .disclosureIndicator) { [unowned self] in
          self.startSelfStudyCurrentLevel()
        }
        model.add(selfStudyItem)

        let listeningItem = BasicModelItem(style: .default, title: "Listening practice",
                                           accessoryType: .disclosureIndicator) { [unowned self] in
          self.startListeningPractice()
        }
        listeningItem.image = UIImage(systemName: "headphones")
        model.add(listeningItem)

        let reverseItem = BasicModelItem(style: .default, title: "Reverse practice",
                                         accessoryType: .disclosureIndicator) { [unowned self] in
          self.startReversePractice()
        }
        reverseItem.image = UIImage(systemName: "arrow.left.arrow.right")
        model.add(reverseItem)
      }

      model.add(section: "Upcoming reviews")
      if !Settings.showForecastChart {
        // Forecast chart hidden in settings; skip it (the review-time row below still shows).
      } else if #available(iOS 15.0, *) {
        model.add(ForecastChartItem(upcomingReviews: upcomingReviews,
                                    currentReviewCount: reviews,
                                    date: Date()) { [unowned self] in self.showTableForecast() })
      } else {
        model.add(UpcomingReviewsChartItem(upcomingReviews: upcomingReviews,
                                           currentReviewCount: reviews,
                                           date: Date()) { [unowned self] in self
            .showTableForecast()
          })
      }
      model
        .add(createCurrentLevelReviewTimeItem(services: services,
                                              currentLevelAssignments: currentLevelAssignments))

      if recentLessonCount > 0 {
        let recentLessonsItem = BasicModelItem(style: .value1,
                                               title: "Review recent lessons",
                                               subtitle: "",
                                               accessoryType: .disclosureIndicator) { [
          unowned self
        ] in
          self.startRecentLessonReviews()
        }
        _ = setTableViewCellCount(recentLessonsItem, count: recentLessonCount)
        model.add(recentLessonsItem)
      }

      if recentMistakes > 0 {
        let recentMistakesItem = BasicModelItem(style: .value1,
                                                title: "Review recent mistakes",
                                                subtitle: "",
                                                accessoryType: .disclosureIndicator) { [
          unowned self
        ] in
          self.startRecentMistakeReviews()
        }
        _ = setTableViewCellCount(recentMistakesItem, count: recentMistakes)
        model.add(recentMistakesItem)
      }

      let alreadyPassedButApprenticeCount = apprenticeCount - recentLessonCount
      if alreadyPassedButApprenticeCount > 0 {
        let alreadyPassedApprenticeItem = BasicModelItem(style: .value1,
                                                         title: "Review apprentice leeches",
                                                         subtitle: "",
                                                         accessoryType: .disclosureIndicator) { [
          unowned self
        ] in
          self.startAlreadyPassedApprenticeReviews()
        }
        _ = setTableViewCellCount(alreadyPassedApprenticeItem,
                                  count: alreadyPassedButApprenticeCount)
        model.add(alreadyPassedApprenticeItem)
      }

      if leechCount > 0 {
        let allLeechItem = BasicModelItem(style: .value1,
                                          title: "Review all leeches",
                                          subtitle: "",
                                          accessoryType: .disclosureIndicator) { [
          unowned self
        ] in
          self.startAllLeechReviews()
        }
        _ = setTableViewCellCount(allLeechItem,
                                  count: leechCount)
        model.add(allLeechItem)
      }
    }

    if #available(iOS 15.0, *), Settings.showActivityWidget {
      model.add(section: "Activity")
      model.add(StreakHeatmapItem(streak: services.localCachingClient.reviewStreak,
                                  dailyCounts: services.localCachingClient.reviewActivityByDay()))
    }

    if Settings.showPreviousLevelGraph, user.currentLevel > 1,
       !services.localCachingClient.hasCompletedPreviousLevel() {
      let previousLevel = Int(user.currentLevel) - 1
      model
        .add(section: "Previous level (\(user.currentLevel - 1))")
      let currentGraphLevelAssignments = services.localCachingClient
        .getAssignments(level: previousLevel)
      addLevelProgress(to: model, assignments: currentGraphLevelAssignments)
      addShowRemainingAllItems(model: model, level: previousLevel)
      // add header for next section; graph and other items will be added after this if/else block
      model.add(section: "Current level (\(user.currentLevel))")
    } else {
      model.add(section: "Current level")
    }

    addLevelProgress(to: model, assignments: currentLevelAssignments)

    if !user.hasVacationStartedAt {
      model
        .add(createLevelTimeRemainingItem(services: services,
                                          currentLevelAssignments: currentLevelAssignments))
    }
    addShowRemainingAllItems(model: model, level: Int(user.currentLevel))

    model.add(section: "All levels")
    if #available(iOS 15.0, *) {
      model.add(SRSDistributionItem(counts: services.localCachingClient.srsCategoryCounts,
                                    accuracy: Settings.showAccuracyStat
                                      ? services.localCachingClient.overallAccuracy : nil))
      let statsItem = BasicModelItem(style: .default, title: "Statistics",
                                     accessoryType: .disclosureIndicator) { [unowned self] in
        let vc = StatsViewController()
        vc.setup(services: self.services)
        self.navigationController?.pushViewController(vc, animated: true)
      }
      statsItem.image = UIImage(systemName: "chart.bar.xaxis")
      statsItem.imageTintColor = TKMStyle.vocabularyColor1
      model.add(statsItem)
    }
    if let interval = services.localCachingClient.averageLevelUpInterval {
      let days = interval / 86400
      let subtitle = days >= 1 ? String(format: "%.1f days", days)
        : String(format: "%.0f hours", interval / 3600)
      model.add(BasicModelItem(style: .value1, title: "Average level-up time",
                               subtitle: subtitle, accessoryType: .none))
    }
    for category in SRSStageCategory.apprentice ... SRSStageCategory.burned {
      let count = services.localCachingClient.srsCategoryCounts[category.rawValue]
      let item = SRSStageCategoryItem(stageCategory: category, count: Int(count),
                                      accessoryType: count > 0 ? .disclosureIndicator : .none)
      if count > 0 {
        item.tapHandler = { [weak self] in
          if let self = self {
            self.selectedSrsStageCategory = category
            self.perform(segue: StoryboardSegue.Main.viewItemsInSrsCategory, sender: self)
          }
        }
      }
      model.add(item)
      if category == SRSStageCategory.burned, count > 0 {
        model.add(BasicModelItem(style: .value1,
                                 title: "Review burned items",
                                 subtitle: "",
                                 accessoryType: .disclosureIndicator) { [unowned self] in
            self.startBurnedItemReviews()
          })
      }
    }

    if Settings.allowExcludeItems {
      let excludedCount = services.localCachingClient.excludedCount()
      if excludedCount > 0 {
        let excludedItems = BasicModelItem(style: .value1,
                                           title: "Excluded items",
                                           accessoryType: .disclosureIndicator) { [
          unowned self
        ] in
          self
            .perform(segue: StoryboardSegue.Main.showExcluded,
                     sender: self)
        }

        _ = setTableViewCellCount(excludedItems, count: excludedCount)
        model.add(excludedItems)
      }
    }

    applySnapshot(from: model)

    // Share a snapshot with the Home Screen widget.
    WidgetSharedData.write(WidgetSharedData.Snapshot(lessons: lessons, reviews: reviews,
                                                     level: Int(user.level),
                                                     streak: services.localCachingClient
                                                       .reviewStreak,
                                                     username: user.username, updatedAt: Date()))
  }

  private func addLevelProgress(to model: MutableTableModel, assignments: [TKMAssignment]) {
    if #available(iOS 15.0, *) {
      model.add(LevelProgressItem(currentLevelAssignments: assignments))
    } else {
      model.add(CurrentLevelChartItem(currentLevelAssignments: assignments))
    }
  }

  private func addShowRemainingAllItems(model: MutableTableModel, level: Int) {
    model.add(BasicModelItem(style: .default,
                             title: "Show remaining",
                             subtitle: nil,
                             accessoryType: .disclosureIndicator) { [weak self] in
        if let self = self {
          self.selectedSubjectCatalogLevel = level
          self.perform(segue: StoryboardSegue.Main.showRemaining, sender: self)
        }
      })
    model.add(BasicModelItem(style: .default,
                             title: "Show all",
                             subtitle: "",
                             accessoryType: .disclosureIndicator) { [weak self] in
        if let self = self {
          self.selectedSubjectCatalogLevel = level
          self.perform(segue: StoryboardSegue.Main.showAll, sender: self)
        }
      })
  }

  // MARK: - UIViewController

  override func prepare(for segue: UIStoryboardSegue, sender _: Any?) {
    switch StoryboardSegue.Main(segue) {
    case .startReviews:
      let assignments = services.localCachingClient.getNonExcludedAssignments()
      var items = ReviewItem.readyForReview(assignments: assignments,
                                            localCachingClient: services.localCachingClient)
      if items.count == 0 {
        return
      }

      items = sortReviewItems(items: items, services: services)

      if Settings.reviewItemsLimitEnabled || Settings.catchUpMode,
         items.count > Settings.reviewItemsLimit {
        print("Truncating \(items.count) review items to \(Settings.reviewItemsLimit)")
        items = Array(items[0 ..< Int(Settings.reviewItemsLimit)])
      }

      let vc = segue.destination as! ReviewContainerViewController
      vc.setup(services: services, items: items)

    case .startRecentMistakeReviews:
      let assignments = services.localCachingClient.getAllRecentMistakeAssignments()
      let items = ReviewItem.readyForRecentMistakesReview(assignments: assignments,
                                                          localCachingClient: services
                                                            .localCachingClient).shuffled()
      if items.count == 0 {
        return
      }

      let vc = segue.destination as! ReviewContainerViewController
      vc.setup(services: services, items: items, isPracticeSession: true)

    case .startRecentLessonReviews:
      let assignments = services.localCachingClient.getAllRecentLessonAssignments()
      let items = ReviewItem.readyForRecentLessonReview(assignments: assignments,
                                                        localCachingClient: services
                                                          .localCachingClient).shuffled()
      if items.count == 0 {
        return
      }

      let vc = segue.destination as! ReviewContainerViewController
      vc.setup(services: services, items: items, isPracticeSession: true)

    case .startAlreadyPassedApprenticeReviews:
      // load apprentice items, then keep the ones that have been passed.
      let apprenticeItems = services.localCachingClient
        .getAssignmentsInCategory(category: SRSStageCategory.apprentice)
      let items = ReviewItem.readyForAlreadyPassedApprenticeReview(assignments: apprenticeItems,
                                                                   localCachingClient: services
                                                                     .localCachingClient).shuffled()
      if items.count == 0 {
        return
      }

      let vc = segue.destination as! ReviewContainerViewController
      vc.setup(services: services, items: items, isPracticeSession: true)

    case .startAllLeechReviews:
      let leechItems = services.localCachingClient.getAllLeeches()
      let items = ReviewItem.readyForLeechReview(assignments: leechItems,
                                                 localCachingClient: services
                                                   .localCachingClient).shuffled()
      if items.count == 0 {
        return
      }

      let vc = segue.destination as! ReviewContainerViewController
      vc.setup(services: services, items: items, isPracticeSession: true)

    case .startBurnedItemReviews:
      let assignments = services.localCachingClient.getAllBurnedAssignments()
      let items = ReviewItem.readyForBurnedReview(assignments: assignments,
                                                  localCachingClient: services
                                                    .localCachingClient).shuffled()
      if items.count == 0 {
        return
      }

      let vc = segue.destination as! ReviewContainerViewController
      vc.setup(services: services, items: items, isPracticeSession: true)

    case .startLessons:
      let assignments = services.localCachingClient.getNonExcludedAssignments()
      var items = ReviewItem.readyForLessons(assignments: assignments,
                                             localCachingClient: services.localCachingClient)
        .shuffled()
      if items.count == 0 {
        return
      }

      if !Settings.randomLessonOrder {
        items = items.sorted(by: { a, b in a.compareForLessons(other: b) })
      }
      if items.count > Settings.lessonBatchSize {
        items = Array(items[0 ..< Int(Settings.lessonBatchSize)])
      }

      let vc = segue.destination as! LessonsViewController
      vc.setup(services: services, items: items)

    case .showLessonPicker:
      let vc = segue.destination as! LessonPickerViewController
      vc.setup(services: services)

    case .showAll:
      let vc = segue.destination as! SubjectCatalogueViewController
      vc.setup(services: services, level: selectedSubjectCatalogLevel)

    case .showRemaining:
      let vc = segue.destination as! SubjectsRemainingViewController
      vc.setup(services: services, level: selectedSubjectCatalogLevel)

    case .showExcluded:
      let vc = segue.destination as! SubjectsExcludedViewController
      vc.setup(services: services, category: selectedSrsStageCategory,
               showAnswers: Settings.subjectCatalogueViewShowAnswers)

    case .tableForecast:
      let vc = segue.destination as! UpcomingReviewsViewController
      vc.setup(services: services)

    case .viewItemsInSrsCategory:
      let vc = segue.destination as! SubjectsByCategoryViewController
      vc.setup(services: services, category: selectedSrsStageCategory,
               showAnswers: Settings.subjectCatalogueViewShowAnswers)

    default:
      break
    }
  }

  // MARK: - Keyboard navigation

  override var keyCommands: [UIKeyCommand]? {
    var ret = [UIKeyCommand]()

    // Press return to keep studying, first lessons then reviews
    if hasLessons, !hasReviews {
      ret.append(UIKeyCommand(input: "\r",
                              modifierFlags: [],
                              action: #selector(startLessons),
                              discoverabilityTitle: "Continue lessons"))
    } else if hasReviews {
      ret.append(UIKeyCommand(input: "\r",
                              modifierFlags: [],
                              action: #selector(startReviews),
                              discoverabilityTitle: "Continue reviews"))
    }

    // Command L to start lessons, if any
    if hasLessons {
      ret.append(UIKeyCommand(input: "l",
                              modifierFlags: [.command],
                              action: #selector(startLessons),
                              discoverabilityTitle: "Start lessons"))
    }

    // Command R to start reviews, if any
    if hasReviews {
      ret.append(UIKeyCommand(input: "r",
                              modifierFlags: [.command],
                              action: #selector(startReviews),
                              discoverabilityTitle: "Start reviews"))
    }

    return ret
  }

  /// Pushes the SwiftUI review engine with the given items.
  private func pushReview(items: [ReviewItem], isPracticeSession: Bool) {
    guard !items.isEmpty else { return }
    let vc = SwiftUIReviewHostingController(services: services, items: items,
                                            isPracticeSession: isPracticeSession)
    navigationController?.pushViewController(vc, animated: true)
  }

  @objc func startReviews() {
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

  @objc func startLessons() {
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
    let vc = LessonsHostingController(services: services, items: items)
    navigationController?.pushViewController(vc, animated: true)
  }

  @objc func showLessonPicker() {
    let vc = LessonPickerHostingController(services: services)
    navigationController?.pushViewController(vc, animated: true)
  }

  @objc func showTableForecast() {
    perform(segue: StoryboardSegue.Main.tableForecast, sender: self)
  }

  @objc func startRecentMistakeReviews() {
    let assignments = services.localCachingClient.getAllRecentMistakeAssignments()
    let items = ReviewItem.readyForRecentMistakesReview(assignments: assignments,
                                                        localCachingClient: services
                                                          .localCachingClient).shuffled()
    pushReview(items: items, isPracticeSession: true)
  }

  @objc func startRecentLessonReviews() {
    let assignments = services.localCachingClient.getAllRecentLessonAssignments()
    let items = ReviewItem.readyForRecentLessonReview(assignments: assignments,
                                                      localCachingClient: services
                                                        .localCachingClient).shuffled()
    pushReview(items: items, isPracticeSession: true)
  }

  @objc func startAlreadyPassedApprenticeReviews() {
    let apprenticeItems = services.localCachingClient
      .getAssignmentsInCategory(category: SRSStageCategory.apprentice)
    let items = ReviewItem.readyForAlreadyPassedApprenticeReview(assignments: apprenticeItems,
                                                                 localCachingClient: services
                                                                   .localCachingClient).shuffled()
    pushReview(items: items, isPracticeSession: true)
  }

  @objc func startAllLeechReviews() {
    let leechItems = services.localCachingClient.getAllLeeches()
    let items = ReviewItem.readyForLeechReview(assignments: leechItems,
                                               localCachingClient: services
                                                 .localCachingClient).shuffled()
    pushReview(items: items, isPracticeSession: true)
  }

  @objc func startBurnedItemReviews() {
    let assignments = services.localCachingClient.getAllBurnedAssignments()
    let items = ReviewItem.readyForBurnedReview(assignments: assignments,
                                                localCachingClient: services
                                                  .localCachingClient).shuffled()
    pushReview(items: items, isPracticeSession: true)
  }

  @objc func startListeningPractice() {
    let vc = ListeningPracticeViewController()
    vc.setup(services: services)
    navigationController?.pushViewController(vc, animated: true)
  }

  @objc func startReversePractice() {
    let vc = ReversePracticeViewController()
    vc.setup(services: services)
    navigationController?.pushViewController(vc, animated: true)
  }

  @objc func startSelfStudyCurrentLevel() {
    let assignments = services.localCachingClient.getAssignmentsAtUsersCurrentLevel()
    let items = ReviewItem.readyForSelfStudy(assignments: assignments,
                                             localCachingClient: services.localCachingClient)
      .shuffled()
    // Practice session: no SRS impact, and works regardless of whether items are currently due.
    pushReview(items: items, isPracticeSession: true)
  }
}

/// Diffable data source that also supplies plain section header titles (which the base
/// UITableViewDiffableDataSource doesn't do on its own).
private class DashboardDataSource: UITableViewDiffableDataSource<String, String> {
  var sectionTitles = [String: String]()

  override func tableView(_: UITableView, titleForHeaderInSection section: Int) -> String? {
    let ids = snapshot().sectionIdentifiers
    guard section < ids.count else { return nil }
    return sectionTitles[ids[section]]
  }
}
