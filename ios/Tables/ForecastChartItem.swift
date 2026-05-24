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

/// A clean, modern upcoming-reviews forecast: hourly bars for the next 24 hours plus a cumulative
/// line, drawn with SwiftUI Canvas in the WaniKani brand colours. Used on iOS 15+; older systems
/// fall back to `UpcomingReviewsChartItem`.
@available(iOS 15.0, *)
class ForecastChartItem: TableModelItem {
  let upcomingReviews: [Int]
  let currentReviewCount: Int
  let date: Date
  let tapHandler: () -> Void

  init(upcomingReviews: [Int], currentReviewCount: Int, date: Date,
       tapHandler: @escaping () -> Void) {
    self.upcomingReviews = upcomingReviews
    self.currentReviewCount = currentReviewCount
    self.date = date
    self.tapHandler = tapHandler
  }

  var cellFactory: TableModelCellFactory {
    .fromDefaultConstructor(cellClass: ForecastChartCell.self)
  }

  var rowHeight: CGFloat? { 150 }

  var diffIdentifier: String {
    "forecast|\(currentReviewCount)|" + upcomingReviews.prefix(24).map(String.init)
      .joined(separator: ",")
  }
}

@available(iOS 15.0, *)
struct ForecastChartView: View {
  let upcoming: [Int]
  let currentCount: Int

  private let hours = 24

  var body: some View {
    let counts = Array(upcoming.prefix(hours))
    let maxHourly = max(counts.max() ?? 0, 1)
    var cumulative = [Int]()
    var running = currentCount
    for c in counts {
      running += c
      cumulative.append(running)
    }
    let maxCumulative = max(cumulative.max() ?? currentCount, 1)
    let totalUpcoming = running

    return VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline) {
        Text("Next 24 hours")
          .font(.subheadline.weight(.semibold))
        Spacer()
        Text("\(totalUpcoming) total")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Canvas { ctx, size in
        let n = counts.count
        guard n > 0 else { return }
        let gap: CGFloat = 2
        let barWidth = max((size.width - CGFloat(n - 1) * gap) / CGFloat(n), 1)
        let chartHeight = size.height

        // Hourly bars.
        for i in 0 ..< n where counts[i] > 0 {
          let h = chartHeight * CGFloat(counts[i]) / CGFloat(maxHourly)
          let x = CGFloat(i) * (barWidth + gap)
          let rect = CGRect(x: x, y: chartHeight - h, width: barWidth, height: h)
          ctx.fill(Path(roundedRect: rect, cornerRadius: min(barWidth / 2, 2.5)),
                   with: .color(Color(uiColor: TKMStyle.radicalColor2)))
        }

        // Cumulative line.
        var line = Path()
        for i in 0 ..< n {
          let x = CGFloat(i) * (barWidth + gap) + barWidth / 2
          let y = chartHeight - chartHeight * CGFloat(cumulative[i]) / CGFloat(maxCumulative)
          if i == 0 { line.move(to: CGPoint(x: x, y: y)) }
          else { line.addLine(to: CGPoint(x: x, y: y)) }
        }
        ctx.stroke(line, with: .color(Color(uiColor: TKMStyle.vocabularyColor2)),
                   style: StrokeStyle(lineWidth: 2, lineJoin: .round))

        // Baseline.
        var base = Path()
        base.move(to: CGPoint(x: 0, y: chartHeight - 0.5))
        base.addLine(to: CGPoint(x: size.width, y: chartHeight - 0.5))
        ctx.stroke(base, with: .color(.secondary.opacity(0.25)), lineWidth: 1)
      }

      HStack {
        Text("Now").font(.caption2).foregroundStyle(.secondary)
        Spacer()
        Text("+12h").font(.caption2).foregroundStyle(.secondary)
        Spacer()
        Text("+24h").font(.caption2).foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 4)
  }
}

@available(iOS 15.0, *)
class ForecastChartCell: TableModelCell {
  @TypedModelItem var item: ForecastChartItem

  private var hostingController: UIHostingController<ForecastChartView>?

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    selectionStyle = .none
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func update() {
    let view = ForecastChartView(upcoming: item.upcomingReviews,
                                 currentCount: item.currentReviewCount)
    if let hostingController = hostingController {
      hostingController.rootView = view
    } else {
      let hc = UIHostingController(rootView: view)
      hc.view.backgroundColor = .clear
      // The chart has no interactive elements; let taps fall through to the table row so the
      // existing "open full forecast" navigation still fires.
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

  override func didSelect() {
    item.tapHandler()
  }
}
