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

// SwiftUI rewrite of UpcomingReviewsViewController: an hourly table of when reviews become
// available, each row broken down by SRS category and subject type in the brand colours.

@available(iOS 15.0, *)
struct UpcomingReviewsScreen: View {
  struct Span: Identifiable {
    let id = UUID()
    let color: Color
    let count: Int
  }

  struct Row: Identifiable {
    let id = UUID()
    let date: String
    let total: Int
    let diff: Int
    let categorySpans: [Span]
    let typeSpans: [Span]
  }

  let rows: [Row]

  var body: some View {
    List {
      Section {
        if rows.isEmpty {
          Text("No upcoming reviews").foregroundStyle(.secondary)
        } else {
          ForEach(rows) { row in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
              Text(row.date)
                .font(.system(size: 14))
              Spacer(minLength: 8)
              breakdown(row)
                .font(.system(size: 14))
                .monospacedDigit()
            }
          }
        }
      } footer: {
        Text("The numbers on the right are: the total number of reviews, new reviews this hour, " +
          "totals broken down by SRS level (apprentice, guru, master, enlightened) and review " +
          "type (radical, kanji, vocabulary).")
      }
    }
  }

  private func breakdown(_ row: Row) -> Text {
    var text = Text("\(row.total) (+\(row.diff)):").foregroundColor(.secondary)
    for span in row.categorySpans {
      text = text + Text(" \(span.count)").foregroundColor(span.color)
    }
    text = text + Text("  ")
    for span in row.typeSpans {
      text = text + Text(" \(span.count)").foregroundColor(span.color)
    }
    return text
  }

  /// Mirrors UpcomingReviewsViewController: cumulative hourly compositions, skipping hours where
  /// the
  /// total is unchanged.
  static func rows(services: TKMServices) -> [Row] {
    guard let lcc = services.localCachingClient else { return [] }

    var cumulative = [ReviewComposition]()
    for data in lcc.availableSubjects.reviewComposition {
      cumulative.append(data + (cumulative.last ?? ReviewComposition()))
    }

    let formatter = DateFormatter()
    formatter.setLocalizedDateFormatFromTemplate("d MMM ha")

    var rows = [Row]()
    for hour in 0 ..< cumulative.count {
      if hour > 0, cumulative[hour].availableReviews == cumulative[hour - 1].availableReviews {
        continue
      }
      let thisHour = cumulative[hour]
      let lastHour = hour > 0 ? cumulative[hour - 1].availableReviews : 0
      let date = Date().addingTimeInterval(TimeInterval(hour * 60 * 60))

      let categorySpans = thisHour.countByCategory.sorted { $0.key.rawValue < $1.key.rawValue }
        .map { Span(color: Color(uiColor: TKMStyle.color(forSRSStageCategory: $0.key)),
                    count: $0.value) }
      let typeSpans = thisHour.countByType.sorted { $0.key.rawValue < $1.key.rawValue }
        .map { Span(color: Color(uiColor: TKMStyle.color2(forSubjectType: $0.key)),
                    count: $0.value) }

      rows.append(Row(date: formatter.string(from: date),
                      total: thisHour.availableReviews,
                      diff: thisHour.availableReviews - lastHour,
                      categorySpans: categorySpans,
                      typeSpans: typeSpans))
    }
    return rows
  }
}
