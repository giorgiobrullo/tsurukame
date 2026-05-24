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

/// Daily review streak + a GitHub-style activity heatmap of the last ~18 weeks. Driven by the
/// `review_history` cache table. iOS 15+.
@available(iOS 15.0, *)
class StreakHeatmapItem: TableModelItem {
  let streak: Int
  let dailyCounts: [String: Int]

  init(streak: Int, dailyCounts: [String: Int]) {
    self.streak = streak
    self.dailyCounts = dailyCounts
  }

  var cellFactory: TableModelCellFactory {
    .fromDefaultConstructor(cellClass: StreakHeatmapCell.self)
  }

  var rowHeight: CGFloat? { 170 }
}

@available(iOS 15.0, *)
struct ActivityHeatmapView: View {
  let streak: Int
  /// Each column is one week of 7 day-counts (top = start of week). -1 marks a future/blank day.
  let columns: [[Int]]

  private let cellSize: CGFloat = 13
  private let spacing: CGFloat = 3

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 6) {
        Image(systemName: "flame.fill")
          .foregroundStyle(Color(uiColor: TKMStyle.explosionColor2))
        Text("\(streak)")
          .font(.title3.weight(.bold))
          .monospacedDigit()
        Text("day streak")
          .font(.subheadline)
          .foregroundStyle(.secondary)
        Spacer()
      }

      HStack(alignment: .top, spacing: spacing) {
        ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
          VStack(spacing: spacing) {
            ForEach(Array(column.enumerated()), id: \.offset) { _, count in
              RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(color(forCount: count))
                .frame(width: cellSize, height: cellSize)
            }
          }
        }
        Spacer(minLength: 0)
      }
    }
    .padding(.vertical, 8)
  }

  private func color(forCount count: Int) -> Color {
    if count < 0 { return .clear }
    if count == 0 { return Color.secondary.opacity(0.15) }
    let base = Color(uiColor: TKMStyle.radicalColor2)
    switch count {
    case 1 ... 2: return base.opacity(0.35)
    case 3 ... 9: return base.opacity(0.55)
    case 10 ... 24: return base.opacity(0.78)
    default: return base
    }
  }
}

@available(iOS 15.0, *)
class StreakHeatmapCell: TableModelCell {
  @TypedModelItem var item: StreakHeatmapItem

  private var hostingController: UIHostingController<ActivityHeatmapView>?

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    selectionStyle = .none
    backgroundColor = TKMStyle.Color.cellBackground
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// Builds 18 week-columns of day counts ending with the current week, aligned to the locale's
  /// first weekday. -1 marks days in the future.
  private static func buildColumns(dailyCounts: [String: Int]) -> [[Int]] {
    let weeks = 18
    let calendar = Calendar.current
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    formatter.dateFormat = "yyyy-MM-dd"

    let today = calendar.startOfDay(for: Date())
    let weekday = calendar.component(.weekday, from: today)
    let daysIntoWeek = (weekday - calendar.firstWeekday + 7) % 7
    guard let startOfThisWeek = calendar.date(byAdding: .day, value: -daysIntoWeek, to: today),
          let startDate = calendar.date(byAdding: .day, value: -7 * (weeks - 1),
                                        to: startOfThisWeek) else { return [] }

    var columns = [[Int]]()
    for col in 0 ..< weeks {
      var column = [Int]()
      for row in 0 ..< 7 {
        guard let day = calendar.date(byAdding: .day, value: col * 7 + row, to: startDate) else {
          column.append(-1)
          continue
        }
        if day > today {
          column.append(-1)
        } else {
          column.append(dailyCounts[formatter.string(from: day)] ?? 0)
        }
      }
      columns.append(column)
    }
    return columns
  }

  override func update() {
    let view = ActivityHeatmapView(streak: item.streak,
                                   columns: StreakHeatmapCell.buildColumns(dailyCounts: item
                                     .dailyCounts))
    if let hostingController = hostingController {
      hostingController.rootView = view
    } else {
      let hc = UIHostingController(rootView: view)
      hc.view.backgroundColor = .clear
      hc.view.isUserInteractionEnabled = false
      hc.view.translatesAutoresizingMaskIntoConstraints = false
      contentView.addSubview(hc.view)
      NSLayoutConstraint.activate([
        hc.view.topAnchor.constraint(equalTo: contentView.topAnchor),
        hc.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        hc.view.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
        hc.view.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
      ])
      hostingController = hc
    }
  }
}
