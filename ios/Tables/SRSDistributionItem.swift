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
@available(iOS 15.0, *)
struct SRSDistributionView: View {
  struct Stage: Identifiable {
    let id = UUID()
    let name: String
    let count: Int
    let color: Color
  }

  let stages: [Stage]
  let accuracy: Double?
  private var total: Int { stages.reduce(0) { $0 + $1.count } }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let accuracy = accuracy {
        HStack(alignment: .firstTextBaseline) {
          Text("Accuracy")
            .font(.subheadline.weight(.semibold))
          Spacer()
          Text("\(Int(accuracy.rounded()))%")
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(accuracy >= 90 ? .green : (accuracy >= 80 ? .primary : .orange))
        }
      }

      GeometryReader { geo in
        HStack(spacing: total > 0 ? 1 : 0) {
          ForEach(stages) { stage in
            stage.color
              .frame(width: max(geo.size.width * CGFloat(stage.count) / CGFloat(max(total, 1)) - 1,
                                0))
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 12)
        .background(Color.secondary.opacity(0.15))
        .clipShape(Capsule())
      }
      .frame(height: 12)

      HStack(spacing: 12) {
        ForEach(stages) { stage in
          HStack(spacing: 5) {
            Circle().fill(stage.color).frame(width: 8, height: 8)
            Text("\(stage.count)")
              .font(.caption2.weight(.semibold))
              .monospacedDigit()
              .foregroundStyle(.primary)
          }
        }
        Spacer(minLength: 0)
      }
    }
    .padding(.vertical, 8)
  }
}

@available(iOS 15.0, *)
extension SRSDistributionView {
  /// Builds the apprentice...burned stage entries from category counts (indexed by
  /// `SRSStageCategory.rawValue`). Shared by the table cell and the SwiftUI dashboard.
  static func stages(from counts: [Int]) -> [Stage] {
    var stages = [Stage]()
    for category in SRSStageCategory.apprentice ... SRSStageCategory.burned {
      let count = category.rawValue < counts.count ? counts[category.rawValue] : 0
      stages.append(Stage(name: category.description, count: count,
                          color: Color(uiColor: TKMStyle.color(forSRSStageCategory: category))))
    }
    return stages
  }
}
