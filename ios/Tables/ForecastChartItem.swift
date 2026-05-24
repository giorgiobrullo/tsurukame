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
import Foundation
import SwiftUI
import UIKit

// The upcoming-reviews forecast for the dashboard, rebuilt with the native SwiftUI Charts
// framework to match the original UIKit chart (UpcomingReviewsChartItem): hourly bars + a
// cumulative line, with real hour labels along the bottom axis.
@available(iOS 16.0, *)
struct ForecastChartView: View {
  let upcoming: [Int]
  let currentCount: Int

  private let hours = 24

  private struct HourPoint: Identifiable {
    let id: Int
    let date: Date
    let hourly: Int
    let cumulative: Int
  }

  private var points: [HourPoint] {
    let counts = Array(upcoming.prefix(hours))
    // Bucket from the next whole hour, so the axis reads like the original ("3PM", "9PM", ...).
    let start = Calendar.current.nextDate(after: Date(),
                                          matching: DateComponents(minute: 0, second: 0),
                                          matchingPolicy: .nextTime) ?? Date()
    var running = currentCount
    return counts.enumerated().map { index, count in
      running += count
      return HourPoint(id: index,
                       date: start.addingTimeInterval(TimeInterval(index * 3600)),
                       hourly: count, cumulative: running)
    }
  }

  var body: some View {
    let pts = points
    let total = pts.last?.cumulative ?? currentCount
    let maxHourly = max(pts.map(\.hourly).max() ?? 1, 1)
    let maxCumulative = max(pts.map(\.cumulative).max() ?? 1, 1)
    // The cumulative line owns the (labelled) y-axis; scale the hourly bars to fill the same
    // height, mirroring the original's hidden second axis for the bars.
    let barScale = Double(maxCumulative) / Double(maxHourly)

    return VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        Text("Next 24 hours").font(.subheadline.weight(.semibold))
        Spacer()
        Text("\(total) total").font(.caption).foregroundStyle(.secondary)
      }

      Chart {
        ForEach(pts) { point in
          BarMark(x: .value("Time", point.date, unit: .hour),
                  y: .value("Reviews", Double(point.hourly) * barScale))
            .foregroundStyle(Color(uiColor: TKMStyle.radicalColor2))
            .opacity(point.hourly > 0 ? 1 : 0)
        }
        ForEach(pts) { point in
          LineMark(x: .value("Time", point.date),
                   y: .value("Total", point.cumulative))
            .foregroundStyle(Color(uiColor: TKMStyle.vocabularyColor2))
            .interpolationMethod(.monotone)
            .lineStyle(StrokeStyle(lineWidth: 2))
        }
      }
      .chartXAxis {
        AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
          AxisGridLine()
          AxisTick()
          AxisValueLabel(format: .dateTime.hour())
        }
      }
      .chartYAxis { AxisMarks(position: .leading) }
      .frame(height: 170)
    }
    .padding(.vertical, 4)
  }
}
