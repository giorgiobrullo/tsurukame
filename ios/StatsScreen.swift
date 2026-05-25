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

import Charts
import SwiftUI
import WaniKaniAPI

// The dedicated Statistics section: a wkstats-style Progress / Items / Charts screen with a
// floating
// Liquid Glass switcher (iOS 26) over the scrolling content. Replaces the old "Statistics" link.

@available(iOS 16.0, *)
struct StatsScreen: View {
  let services: TKMServices
  let onTapSubject: (Int64) -> Void
  @StateObject private var loader = StatsLoader()
  @State private var tab: StatsTab = .progress
  @Namespace private var pill

  enum StatsTab: String, CaseIterable, Identifiable {
    case progress = "Progress"
    case items = "Items"
    case charts = "Charts"
    var id: String { rawValue }
    var icon: String {
      switch self {
      case .progress: return "chart.line.uptrend.xyaxis"
      case .items: return "square.grid.3x3.fill"
      case .charts: return "chart.bar.xaxis"
      }
    }
  }

  var body: some View {
    ZStack(alignment: .bottom) {
      Color.tkmBackground.ignoresSafeArea()
      content
      switcher.padding(.bottom, 10)
    }
    .navigationTitle("Statistics")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear { loader.load(services) }
  }

  @ViewBuilder private var content: some View {
    if let model = loader.model {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          switch tab {
          case .progress: StatsProgressTab(model: model)
          case .items: StatsItemsTab(model: model, onTapSubject: onTapSubject)
          case .charts: StatsChartsTab(model: model)
          }
        }
        .padding(16)
        .padding(.bottom, 78) // clearance for the floating switcher
      }
    } else {
      ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private var switcher: some View {
    let bar = HStack(spacing: 4) {
      ForEach(StatsTab.allCases) { t in
        Button {
          withAnimation(.easeInOut(duration: 0.22)) { tab = t }
        } label: {
          HStack(spacing: 6) {
            Image(systemName: t.icon)
            Text(t.rawValue)
          }
          .font(.subheadline.weight(.semibold))
          .padding(.horizontal, 16)
          .padding(.vertical, 10)
          .foregroundStyle(tab == t ? Color.white : Color.tkmLabel)
          .background {
            if tab == t {
              Capsule().fill(Color.tkmTint).matchedGeometryEffect(id: "pill", in: pill)
            }
          }
          .contentShape(Capsule())
        }
        .buttonStyle(.plain)
      }
    }
    .padding(5)

    return glassCapsule(bar).shadow(color: .black.opacity(0.18), radius: 14, y: 5)
  }

  @ViewBuilder private func glassCapsule(_ view: some View) -> some View {
    if #available(iOS 26.0, *) {
      view.glassEffect(.regular.interactive(), in: .capsule)
    } else {
      view.background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
    }
  }
}

// MARK: - Progress tab

@available(iOS 16.0, *)
struct StatsProgressTab: View {
  let model: StatsModel

  var body: some View {
    LazyVStack(alignment: .leading, spacing: 16) {
      summary
      if model.projectedLevel60 != nil || model.avgLevelUpDays != nil { projection }
      if !model.levelUps.isEmpty { levelUpChart }
      srs
      if !model.coverage.isEmpty { coverage }
    }
  }

  private var summary: some View {
    let cols = [GridItem(.flexible()), GridItem(.flexible())]
    return LazyVGrid(columns: cols, spacing: 12) {
      StatTile(value: "\(model.level)", caption: "current level",
               systemImage: "arrow.up.circle.fill", tint: .tkmRadical)
      StatTile(value: "\(model.streak)",
               caption: model.longestStreak > 0 ? "streak · best \(model.longestStreak)"
                 : "day streak",
               systemImage: "flame.fill", tint: Color(uiColor: TKMStyle.explosionColor2))
      StatTile(value: model.accuracy.map { "\(Int($0.rounded()))%" } ?? "–",
               caption: "accuracy", systemImage: "target", tint: .green)
      StatTile(value: "\(model.totalStarted)", caption: "items started",
               systemImage: "square.stack.3d.up.fill", tint: .tkmVocabulary)
    }
  }

  private var projection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Projection").font(.headline)
      if let date = model.projectedLevel60 {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text("Level 60 around").foregroundStyle(.secondary)
          Spacer()
          Text(date.formatted(.dateTime.month().year()))
            .font(.title3.weight(.bold))
            .foregroundStyle(Color.tkmRadical)
        }
      }
      Divider()
      statRow("Average level-up", model.avgLevelUpDays.map { String(format: "%.1f days", $0) })
      if let f = model.fastestLevelUp {
        statRow("Fastest", String(format: "%.1f days · L%d", f.days, f.level))
      }
      if let s = model.slowestLevelUp {
        statRow("Slowest", String(format: "%.1f days · L%d", s.days, s.level))
      }
      if let d = model.daysOnWaniKani { statRow("Days on WaniKani", "\(d)") }
    }
    .tkmCard()
  }

  private var levelUpChart: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Days per level").font(.subheadline.weight(.semibold))
      Chart(model.levelUps) { lu in
        BarMark(x: .value("Level", lu.level), y: .value("Days", lu.days))
          .foregroundStyle(Color(uiColor: TKMStyle.radicalColor2))
      }
      .chartXAxis { AxisMarks(values: .stride(by: 5)) }
      .frame(height: 170)
    }
    .tkmCard()
  }

  private var srs: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("SRS stages").font(.subheadline.weight(.semibold))
      SRSDistributionView(stages: model.srsStages, accuracy: nil)
    }
    .tkmCard()
  }

  private var coverage: some View {
    VStack(alignment: .leading, spacing: 16) {
      ForEach(["JLPT", "Jōyō"], id: \.self) { section in
        let groups = model.coverage.filter { $0.section == section }
        if !groups.isEmpty {
          VStack(alignment: .leading, spacing: 10) {
            Text(section == "JLPT" ? "JLPT kanji" : "Jōyō kanji")
              .font(.subheadline.weight(.semibold))
            ForEach(groups) { CoverageBar(group: $0) }
          }
          .tkmCard()
        }
      }
    }
  }

  private func statRow(_ label: String, _ value: String?) -> some View {
    HStack {
      Text(label).foregroundStyle(.secondary)
      Spacer()
      Text(value ?? "–").fontWeight(.semibold).monospacedDigit()
    }
    .font(.subheadline)
  }
}

// MARK: - Charts tab

@available(iOS 16.0, *)
struct StatsChartsTab: View {
  let model: StatsModel

  var body: some View {
    LazyVStack(alignment: .leading, spacing: 16) {
      accuracy
      if model.currentReviewCount > 0 || model.upcomingReviews.contains(where: { $0 > 0 }) {
        VStack(alignment: .leading, spacing: 8) {
          Text("Upcoming reviews").font(.subheadline.weight(.semibold))
          ForecastChartView(upcoming: model.upcomingReviews, currentCount: model.currentReviewCount)
        }
        .tkmCard()
      }
      if !model.reviewsPerDay.isEmpty { reviewsPerDay }
      VStack(alignment: .leading, spacing: 4) {
        ActivityHeatmapView(streak: model.streak, columns: model.heatmapColumns)
      }
      .tkmCard()
    }
  }

  private var accuracy: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        Text("Accuracy").font(.headline)
        Spacer()
        Text(model.accuracy.map { "\(Int($0.rounded()))%" } ?? "–")
          .font(.title2.weight(.bold)).monospacedDigit()
          .foregroundStyle(.green)
      }
      accuracyRow("Meaning", model.meaningAccuracy, Color(uiColor: TKMStyle.kanjiColor2))
      accuracyRow("Reading", model.readingAccuracy, Color(uiColor: TKMStyle.radicalColor2))
    }
    .tkmCard()
  }

  private func accuracyRow(_ label: String, _ value: Double?, _ tint: Color) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(label).font(.subheadline)
        Spacer()
        Text(value.map { "\(Int($0.rounded()))%" } ?? "–")
          .font(.subheadline.weight(.semibold)).monospacedDigit()
      }
      GeometryReader { geo in
        ZStack(alignment: .leading) {
          Capsule().fill(Color.secondary.opacity(0.15))
          Capsule().fill(tint)
            .frame(width: geo.size.width * CGFloat((value ?? 0) / 100))
        }
      }
      .frame(height: 8)
    }
  }

  private var reviewsPerDay: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Reviews per day").font(.subheadline.weight(.semibold))
      Chart(model.reviewsPerDay) { day in
        BarMark(x: .value("Day", day.date, unit: .day),
                y: .value("Reviews", day.count))
          .foregroundStyle(Color(uiColor: TKMStyle.vocabularyColor2))
      }
      .chartXAxis { AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
        AxisGridLine()
        AxisTick()
        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
      } }
      .frame(height: 150)
    }
    .tkmCard()
  }
}

// MARK: - Items tab

@available(iOS 16.0, *)
struct StatsItemsTab: View {
  let model: StatsModel
  let onTapSubject: (Int64) -> Void
  @State private var filter: TypeFilter = .all

  enum TypeFilter: String, CaseIterable, Identifiable {
    case all = "All", radical = "Radicals", kanji = "Kanji", vocab = "Vocab"
    var id: String { rawValue }
    func matches(_ type: TKMSubject.TypeEnum) -> Bool {
      switch self {
      case .all: return true
      case .radical: return type == .radical
      case .kanji: return type == .kanji
      case .vocab: return type == .vocabulary
      }
    }
  }

  private let cols = [GridItem(.adaptive(minimum: 34, maximum: 40), spacing: 6)]

  var body: some View {
    LazyVStack(alignment: .leading, spacing: 16, pinnedViews: []) {
      Picker("Type", selection: $filter) {
        ForEach(TypeFilter.allCases) { Text($0.rawValue).tag($0) }
      }
      .pickerStyle(.segmented)

      legend

      if !model.criticalItems.isEmpty { critical }

      ForEach(model.itemLevels) { level in
        let items = level.items.filter { filter.matches($0.subject.subjectType) }
        if !items.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Text("Level \(level.level)").font(.subheadline.weight(.semibold))
            LazyVGrid(columns: cols, spacing: 6) {
              ForEach(items) { item in
                ItemTile(item: item, onTap: onTapSubject)
              }
            }
          }
          .tkmCard()
        }
      }
    }
  }

  private var legend: some View {
    let stages: [(String, SRSStageCategory)] = [("Appr.", .apprentice), ("Guru", .guru),
                                                ("Master", .master), ("Enlt.", .enlightened),
                                                ("Burned", .burned)]
    return HStack(spacing: 12) {
      ForEach(stages, id: \.0) { name, cat in
        HStack(spacing: 4) {
          RoundedRectangle(cornerRadius: 3)
            .fill(Color(uiColor: TKMStyle.color(forSRSStageCategory: cat)))
            .frame(width: 10, height: 10)
          Text(name).font(.caption2).foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 0)
    }
  }

  private var critical: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        Text("Critical items").font(.subheadline.weight(.semibold))
        Spacer()
        Text("lowest accuracy").font(.caption).foregroundStyle(.secondary)
      }
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(model.criticalItems) { item in
            Button { onTapSubject(item.subject.id) } label: {
              VStack(spacing: 4) {
                JapaneseSubjectLabel(subject: item.subject, size: 20)
                  .frame(height: 26)
                Text("\(Int(item.accuracy.rounded()))%")
                  .font(.caption2.weight(.bold)).monospacedDigit()
                  .foregroundStyle(.white)
              }
              .padding(.horizontal, 10).padding(.vertical, 8)
              .background(Color(uiColor: TKMStyle.color2(forSubjectType: item.subject.subjectType)))
              .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
    .tkmCard()
  }
}

// MARK: - Small components

@available(iOS 15.0, *)
struct StatTile: View {
  let value: String
  let caption: String
  let systemImage: String
  let tint: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Image(systemName: systemImage).foregroundStyle(tint)
      Text(value)
        .font(.system(size: 28, weight: .bold, design: .rounded))
        .minimumScaleFactor(0.5).lineLimit(1)
      Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .tkmCard(cornerRadius: 14)
  }
}

@available(iOS 15.0, *)
struct CoverageBar: View {
  let group: StatsModel.CoverageGroup

  private var fraction: Double {
    group.taught > 0 ? Double(group.passed) / Double(group.taught) : 0
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 4) {
        Text(group.name).font(.subheadline)
        Spacer()
        Text("\(group.passed)/\(group.taught)")
          .font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(.secondary)
        if group.taught < group.total {
          Text("of \(group.total)").font(.caption2).foregroundStyle(.tertiary)
        }
      }
      GeometryReader { geo in
        ZStack(alignment: .leading) {
          Capsule().fill(Color.secondary.opacity(0.15))
          Capsule().fill(group.color).frame(width: geo.size.width * CGFloat(fraction))
        }
      }
      .frame(height: 8)
    }
  }
}

@available(iOS 15.0, *)
struct ItemTile: View {
  let item: StatsModel.Item
  let onTap: (Int64) -> Void

  private var background: Color {
    if let category = item.category {
      return Color(uiColor: TKMStyle.color(forSRSStageCategory: category))
    }
    return Color.secondary.opacity(0.25) // locked / not started
  }

  var body: some View {
    Button { onTap(item.subject.id) } label: {
      JapaneseSubjectLabel(subject: item.subject, size: 17)
        .frame(width: 34, height: 34)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .opacity(item.category == nil ? 0.6 : 1)
    }
    .buttonStyle(.plain)
  }
}
