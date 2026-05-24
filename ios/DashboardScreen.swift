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

// MARK: - Data

/// A flat, render-ready snapshot of everything the dashboard shows. Built off `LocalCachingClient`
/// (the same accessors the UIKit dashboard reads), so the SwiftUI dashboard is a pure function of
/// this struct. This is the first screen of the SwiftUI rewrite (issue #62 / the multiplatform
/// migration); it composes the existing reusable widget views (ForecastChartView,
/// LevelProgressView,
/// SRSDistributionView, ActivityHeatmapView).
@available(iOS 15.0, *)
struct DashboardData {
  var username: String
  var level: Int
  var onVacation: Bool

  var lessonCount: Int
  var reviewCardCount: Int
  var totalReviewCount: Int
  var lessonsEnabled: Bool
  var reviewsEnabled: Bool
  var lessonsSubtitle: String
  var reviewsSubtitle: String
  var showLessonPicker: Bool
  var showReviewOrder: Bool
  var reviewOrder: String

  var showForecast: Bool
  var upcomingReviews: [Int]

  var showActivity: Bool
  var streak: Int
  var heatmapColumns: [[Int]]

  var levelRows: [LevelProgressView.Row]

  var srsStages: [SRSDistributionView.Stage]
  var accuracy: Double?

  var selfStudyCount: Int
  var recentLessons: Int
  var recentMistakes: Int
  var apprenticeLeeches: Int
  var leeches: Int

  /// Mirrors `MainWaniKaniTabViewController.recreateTableModel()` so the two dashboards agree.
  static func make(from services: TKMServices) -> DashboardData? {
    guard let lcc = services.localCachingClient, let user = lcc.getUserInfo() else { return nil }

    let lessons = lcc.availableLessonCount
    let reviews = lcc.availableReviewCount
    let apprenticeCount = lcc.apprenticeCount
    let limit = Settings.apprenticeLessonsLimit
    let lessonsAtLimit = apprenticeCount >= limit
    let lessonsEnabled = lessons > 0 && !lessonsAtLimit
    let reviewsEnabled = reviews > 0

    let lessonsSubtitle = lessonsAtLimit ? "Apprentice limit reached"
      : (lessons == 1 ? "lesson to learn" : "lessons to learn")

    // Catch-up mode: present a manageable batch instead of the full (discouraging) backlog.
    let catchUpBatch = Int(Settings.reviewItemsLimit)
    let catchingUp = Settings.catchUpMode && reviews > catchUpBatch
    let reviewCardCount = catchingUp ? catchUpBatch : reviews
    let reviewsSubtitle = catchingUp ? "of \(reviews) waiting"
      : (reviews == 1 ? "review to do" : "reviews to do")

    let currentLevelAssignments = lcc.getAssignmentsAtUsersCurrentLevel()
    let selfStudyCount = currentLevelAssignments.filter { $0.isReviewStage }.count
    let recentLessons = lcc.recentLessonCount

    return DashboardData(username: user.username,
                         level: Int(user.currentLevel),
                         onVacation: user.hasVacationStartedAt,
                         lessonCount: lessons,
                         reviewCardCount: reviewCardCount,
                         totalReviewCount: reviews,
                         lessonsEnabled: lessonsEnabled,
                         reviewsEnabled: reviewsEnabled,
                         lessonsSubtitle: lessonsSubtitle,
                         reviewsSubtitle: reviewsSubtitle,
                         showLessonPicker: lessons > 0 && apprenticeCount < limit,
                         showReviewOrder: reviews > 0,
                         reviewOrder: Settings.reviewOrder.description,
                         showForecast: Settings.showForecastChart,
                         upcomingReviews: lcc.upcomingReviews,
                         showActivity: Settings.showActivityWidget,
                         streak: lcc.reviewStreak,
                         heatmapColumns: ActivityHeatmapView
                           .columns(from: lcc.reviewActivityByDay()),
                         levelRows: LevelProgressView.rows(from: currentLevelAssignments),
                         srsStages: SRSDistributionView.stages(from: lcc.srsCategoryCounts),
                         accuracy: Settings.showAccuracyStat ? lcc.overallAccuracy : nil,
                         selfStudyCount: selfStudyCount,
                         recentLessons: recentLessons,
                         recentMistakes: lcc.getRecentMistakesCount(),
                         apprenticeLeeches: max(apprenticeCount - recentLessons, 0),
                         leeches: lcc.leechCount)
  }
}

/// Navigation callbacks, wired by the host controller to the existing UIKit flows.
@available(iOS 15.0, *)
struct DashboardActions {
  var startLessons: () -> Void = {}
  var startReviews: () -> Void = {}
  var showLessonPicker: () -> Void = {}
  var showReviewOrder: () -> Void = {}
  var openForecast: () -> Void = {}
  var selfStudy: () -> Void = {}
  var listening: () -> Void = {}
  var reverse: () -> Void = {}
  var recentLessons: () -> Void = {}
  var recentMistakes: () -> Void = {}
  var apprenticeLeeches: () -> Void = {}
  var allLeeches: () -> Void = {}
  var openStatistics: () -> Void = {}
  var showAllCurrentLevel: () -> Void = {}
}

@available(iOS 15.0, *)
final class DashboardModel: ObservableObject {
  @Published var data: DashboardData?
  var actions = DashboardActions()
}

// MARK: - View

@available(iOS 15.0, *)
struct DashboardScreen: View {
  @ObservedObject var model: DashboardModel
  var onRefresh: () -> Void

  var body: some View {
    ScrollView {
      if let data = model.data {
        content(data)
          .padding(.horizontal, 16)
          .padding(.vertical, 18)
      } else {
        ProgressView()
          .padding(.top, 80)
          .frame(maxWidth: .infinity)
      }
    }
    .background(Color(uiColor: TKMStyle.Color.background))
    .refreshable { onRefresh() }
  }

  @ViewBuilder
  private func content(_ data: DashboardData) -> some View {
    VStack(alignment: .leading, spacing: 20) {
      if data.onVacation {
        vacationBanner
      } else {
        actionSection(data)
        if data.selfStudyCount > 0 { practiceSection(data) }
        if data.showForecast || data.totalReviewCount > 0 { forecastSection(data) }
        extraReviewsSection(data)
      }

      if data.showActivity {
        TKMSection("Activity") {
          ActivityHeatmapView(streak: data.streak, columns: data.heatmapColumns).tkmCard()
        }
      }

      TKMSection("Current level \(data.level)") {
        VStack(spacing: 10) {
          LevelProgressView(rows: data.levelRows).tkmCard()
          TKMNavRow("Show all items", systemImage: "square.grid.2x2",
                    action: model.actions.showAllCurrentLevel)
        }
      }

      allLevelsSection(data)
    }
  }

  // MARK: Sections

  private func actionSection(_ data: DashboardData) -> some View {
    VStack(spacing: 12) {
      HStack(spacing: 12) {
        actionCard(title: "Lessons", count: data.lessonCount, subtitle: data.lessonsSubtitle,
                   enabled: data.lessonsEnabled,
                   gradient: [TKMStyle.vocabularyColor1, TKMStyle.kanjiColor1],
                   action: model.actions.startLessons)
        actionCard(title: "Reviews", count: data.reviewCardCount, subtitle: data.reviewsSubtitle,
                   enabled: data.reviewsEnabled,
                   gradient: [TKMStyle.radicalColor1, TKMStyle.radicalColor2],
                   action: model.actions.startReviews)
      }
      if data.showLessonPicker {
        TKMNavRow("Lesson Picker", systemImage: "square.grid.2x2",
                  action: model.actions.showLessonPicker)
      }
      if data.showReviewOrder {
        TKMNavRow("Review order", subtitle: data.reviewOrder, systemImage: "arrow.up.arrow.down",
                  action: model.actions.showReviewOrder)
      }
    }
  }

  private func practiceSection(_ data: DashboardData) -> some View {
    TKMSection("Practice") {
      VStack(spacing: 10) {
        TKMNavRow("Self-study current level", subtitle: "\(data.selfStudyCount)",
                  systemImage: "rectangle.stack", action: model.actions.selfStudy)
        TKMNavRow("Listening practice", systemImage: "headphones",
                  action: model.actions.listening)
        TKMNavRow("Reverse practice", systemImage: "arrow.left.arrow.right",
                  action: model.actions.reverse)
      }
    }
  }

  private func forecastSection(_ data: DashboardData) -> some View {
    TKMSection("Upcoming reviews") {
      if data.showForecast {
        Button(action: model.actions.openForecast) {
          ForecastChartView(upcoming: data.upcomingReviews, currentCount: data.totalReviewCount)
            .tkmCard()
        }
        .buttonStyle(.plain)
      }
    }
  }

  @ViewBuilder
  private func extraReviewsSection(_ data: DashboardData) -> some View {
    let hasAny = data.recentLessons > 0 || data.recentMistakes > 0
      || data.apprenticeLeeches > 0 || data.leeches > 0
    if hasAny {
      VStack(spacing: 10) {
        if data.recentLessons > 0 {
          TKMNavRow("Review recent lessons", subtitle: "\(data.recentLessons)",
                    systemImage: "clock.arrow.circlepath", action: model.actions.recentLessons)
        }
        if data.recentMistakes > 0 {
          TKMNavRow("Review recent mistakes", subtitle: "\(data.recentMistakes)",
                    systemImage: "xmark.circle", action: model.actions.recentMistakes)
        }
        if data.apprenticeLeeches > 0 {
          TKMNavRow("Review apprentice leeches", subtitle: "\(data.apprenticeLeeches)",
                    systemImage: "leaf", action: model.actions.apprenticeLeeches)
        }
        if data.leeches > 0 {
          TKMNavRow("Review all leeches", subtitle: "\(data.leeches)",
                    systemImage: "ant", action: model.actions.allLeeches)
        }
      }
    }
  }

  private func allLevelsSection(_ data: DashboardData) -> some View {
    TKMSection("All levels") {
      VStack(spacing: 10) {
        SRSDistributionView(stages: data.srsStages, accuracy: data.accuracy).tkmCard()
        TKMNavRow("Statistics", systemImage: "chart.bar.xaxis",
                  tint: Color(uiColor: TKMStyle.vocabularyColor1),
                  action: model.actions.openStatistics)
      }
    }
  }

  private var vacationBanner: some View {
    HStack(spacing: 12) {
      Image(systemName: "beach.umbrella.fill")
        .font(.title2)
        .foregroundStyle(Color.tkmRadical)
      VStack(alignment: .leading, spacing: 2) {
        Text("Vacation mode")
          .font(.headline)
        Text("Reviews are paused until you turn it off.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      Spacer()
    }
    .tkmCard()
  }

  // MARK: Action cards

  private func actionCard(title: String, count: Int, subtitle: String, enabled: Bool,
                          gradient: [UIColor], action: @escaping () -> Void) -> some View {
    Button(action: { if enabled { action() } }) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.headline)
          .foregroundStyle(.white.opacity(0.95))
        Text("\(count)")
          .font(.system(size: 42, weight: .bold, design: .rounded))
          .foregroundStyle(.white)
          .minimumScaleFactor(0.5)
          .lineLimit(1)
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(.white.opacity(0.9))
          .lineLimit(1)
          .minimumScaleFactor(0.7)
      }
      .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
      .padding(18)
      .background(LinearGradient(colors: gradient.map { Color(uiColor: $0) },
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
      .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
      .opacity(enabled ? 1 : 0.45)
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
  }

  private func row(_ title: String, subtitle: String? = nil, systemImage: String,
                   tint: Color = Color(uiColor: TKMStyle.defaultTintColor),
                   action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: systemImage)
          .foregroundStyle(tint)
          .frame(width: 24)
        Text(title)
          .foregroundStyle(Color(uiColor: TKMStyle.Color.label))
        Spacer(minLength: 8)
        if let subtitle = subtitle {
          Text(subtitle)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.tertiary)
      }
      .padding(.vertical, 13)
      .padding(.horizontal, 16)
      .frame(maxWidth: .infinity)
      .background(Color(uiColor: TKMStyle.Color.cellBackground))
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    .buttonStyle(.plain)
  }
}
