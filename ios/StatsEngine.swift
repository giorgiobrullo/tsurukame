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

import Combine
import Foundation
import SwiftUI
import WaniKaniAPI

// Data layer for the dedicated Statistics section (the wkstats-style Progress / Items / Charts
// screen). Everything is derived from the local cache, built off the main thread, and published as
// an immutable snapshot.

// MARK: - Model

@available(iOS 15.0, *)
struct StatsModel {
  // Summary
  let level: Int
  let streak: Int
  let longestStreak: Int
  let accuracy: Double?
  let meaningAccuracy: Double?
  let readingAccuracy: Double?
  let totalStarted: Int
  let daysOnWaniKani: Int?

  // SRS distribution
  let srsStages: [SRSDistributionView.Stage]

  // Progress
  let levelUps: [LevelUp]
  let avgLevelUpDays: Double?
  let fastestLevelUp: LevelUp?
  let slowestLevelUp: LevelUp?
  let projectedLevel60: Date?

  // Charts
  let upcomingReviews: [Int]
  let currentReviewCount: Int
  let heatmapColumns: [[Int]]
  let reviewsPerDay: [DayCount]

  // Items
  let itemLevels: [ItemLevel]
  let criticalItems: [CriticalItem]

  // Coverage (JLPT / Jōyō)
  let coverage: [CoverageGroup]

  struct LevelUp: Identifiable {
    var id: Int { level }
    let level: Int
    let days: Double
  }

  struct DayCount: Identifiable {
    var id: Date { date }
    let date: Date
    let count: Int
  }

  struct Item: Identifiable {
    var id: Int64 { subject.id }
    let subject: TKMSubject
    let category: SRSStageCategory? // nil = locked / not started
  }

  struct ItemLevel: Identifiable {
    var id: Int { level }
    let level: Int
    let items: [Item]
  }

  struct CriticalItem: Identifiable {
    var id: Int64 { subject.id }
    let subject: TKMSubject
    let accuracy: Double
    let total: Int
  }

  /// A JLPT level or Jōyō grade and how much of it the user has reached Guru+ on (counting only
  /// kanji WaniKani teaches).
  struct CoverageGroup: Identifiable {
    var id: String { section + name }
    let section: String // "JLPT" or "Jōyō"
    let name: String
    let passed: Int // Guru+
    let taught: Int // exists as a WaniKani kanji subject
    let total: Int // kanji in this group overall
    let color: Color
  }
}

// MARK: - Loader

/// Loads a `StatsModel` off the main thread and publishes it. Mirrors the search loader pattern.
@available(iOS 15.0, *)
final class StatsLoader: ObservableObject {
  @Published var model: StatsModel?
  private var started = false

  func load(_ services: TKMServices) {
    guard !started, let lcc = services.localCachingClient else { return }
    started = true
    DispatchQueue.global(qos: .userInitiated).async {
      let model = StatsBuilder.build(lcc: lcc)
      DispatchQueue.main.async { self.model = model }
    }
  }
}

// MARK: - Builder

@available(iOS 15.0, *)
enum StatsBuilder {
  static func build(lcc: LocalCachingClient) -> StatsModel {
    let user = lcc.getUserInfo()
    let level = Int(user?.level ?? 0)

    let counts = lcc.srsStageCounts()
    let categoryCounts = SRSDistributionView.stages(from: lcc.srsCategoryCounts)
    let totalStarted = counts[1 ..< min(10, counts.count)].reduce(0, +)
    let byType = lcc.accuracyByType()

    let (levelUps, avg, fastest, slowest, projected, daysOn) =
      levelProgress(lcc: lcc, currentLevel: level)

    let reviewsPerDay = dayCounts(from: lcc.reviewActivityByDay())
    let heatmap = ActivityHeatmapView.columns(from: lcc.reviewActivityByDay())

    let (itemLevels, subjectsById) = items(lcc: lcc)
    let critical = criticalItems(lcc: lcc, subjectsById: subjectsById)
    let coverage = KanjiReference.coverage(lcc: lcc, subjectsById: subjectsById)

    return StatsModel(level: level,
                      streak: lcc.reviewStreak,
                      longestStreak: lcc.longestStreak,
                      accuracy: lcc.overallAccuracy,
                      meaningAccuracy: byType.meaning,
                      readingAccuracy: byType.reading,
                      totalStarted: totalStarted,
                      daysOnWaniKani: daysOn,
                      srsStages: categoryCounts,
                      levelUps: levelUps,
                      avgLevelUpDays: avg,
                      fastestLevelUp: fastest,
                      slowestLevelUp: slowest,
                      projectedLevel60: projected,
                      upcomingReviews: lcc.upcomingReviews,
                      currentReviewCount: lcc.availableReviewCount,
                      heatmapColumns: heatmap,
                      reviewsPerDay: reviewsPerDay,
                      itemLevels: itemLevels,
                      criticalItems: critical,
                      coverage: coverage)
  }

  // MARK: Level progress + projection

  private static func levelProgress(lcc: LocalCachingClient, currentLevel: Int)
    -> (levelUps: [StatsModel.LevelUp], avg: Double?, fastest: StatsModel.LevelUp?,
        slowest: StatsModel.LevelUp?, projected: Date?, daysOn: Int?) {
    let progressions = lcc.getAllLevelProgressions()
    var levelUps = [StatsModel.LevelUp]()
    var earliestUnlock: Int32?

    for level in progressions {
      let unlocked = level.unlockedAt != 0 ? level.unlockedAt : level.createdAt
      if unlocked != 0 { earliestUnlock = min(earliestUnlock ?? unlocked, unlocked) }
      guard level.hasPassedAt else { continue }
      let start = level.startedAt != 0 ? level.startedAt : level.unlockedAt
      guard start != 0, level.passedAt > start else { continue }
      let days = Double(level.passedAt - start) / 86400
      levelUps.append(.init(level: Int(level.level), days: days))
    }
    levelUps.sort { $0.level < $1.level }

    let intervals = levelUps.map(\.days)
    let avg = intervals.isEmpty ? nil : intervals.reduce(0, +) / Double(intervals.count)
    let fastest = levelUps.min { $0.days < $1.days }
    let slowest = levelUps.max { $0.days < $1.days }

    // Project the level-60 date from the recent pace (the last few level-ups predict the near
    // future better than the lifetime average).
    var projected: Date?
    if (1 ..< 60).contains(currentLevel), !intervals.isEmpty {
      let recent = Array(intervals.suffix(5))
      let pace = recent.reduce(0, +) / Double(recent.count)
      let remaining = Double(60 - currentLevel)
      projected = Date().addingTimeInterval(remaining * pace * 86400)
    }

    let daysOn = earliestUnlock.map { Int(Date().timeIntervalSince1970 - Double($0)) / 86400 }
    return (levelUps, avg, fastest, slowest, projected, daysOn)
  }

  // MARK: Reviews per day

  private static func dayCounts(from daily: [String: Int]) -> [StatsModel.DayCount] {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd"
    let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date.distantPast
    return daily.compactMap { key, count -> StatsModel.DayCount? in
      guard let date = formatter.date(from: key), date >= cutoff else { return nil }
      return StatsModel.DayCount(date: date, count: count)
    }.sorted { $0.date < $1.date }
  }

  // MARK: Items grid

  private static func items(lcc: LocalCachingClient)
    -> (levels: [StatsModel.ItemLevel], byId: [Int64: TKMSubject]) {
    var stageById = [Int64: SRSStageCategory]()
    for assignment in lcc.getAllAssignments() where !assignment.isLocked {
      stageById[assignment.subjectID] = assignment.srsStage.category
    }

    var subjectsById = [Int64: TKMSubject]()
    var byLevel = [Int: [StatsModel.Item]]()
    for subject in lcc.getAllSubjects() {
      guard subject.subjectType != .unknown else { continue }
      subjectsById[subject.id] = subject
      let item = StatsModel.Item(subject: subject, category: stageById[subject.id])
      byLevel[Int(subject.level), default: []].append(item)
    }

    let typeOrder: [TKMSubject.TypeEnum: Int] = [.radical: 0, .kanji: 1, .vocabulary: 2]
    let levels = byLevel.keys.sorted().map { level -> StatsModel.ItemLevel in
      let items = byLevel[level]!.sorted { a, b in
        let ta = typeOrder[a.subject.subjectType] ?? 3
        let tb = typeOrder[b.subject.subjectType] ?? 3
        return ta != tb ? ta < tb : a.subject.id < b.subject.id
      }
      return StatsModel.ItemLevel(level: level, items: items)
    }
    return (levels, subjectsById)
  }

  // MARK: Critical items

  private static func criticalItems(lcc: LocalCachingClient,
                                    subjectsById: [Int64: TKMSubject])
    -> [StatsModel.CriticalItem] {
    lcc.accuracyBySubject()
      .filter { $0.total >= 8 && $0.accuracy < 90 }
      .sorted { $0.accuracy < $1.accuracy }
      .prefix(40)
      .compactMap { entry -> StatsModel.CriticalItem? in
        guard let subject = subjectsById[entry.subjectId] else { return nil }
        return StatsModel.CriticalItem(subject: subject, accuracy: entry.accuracy,
                                       total: entry.total)
      }
  }
}
