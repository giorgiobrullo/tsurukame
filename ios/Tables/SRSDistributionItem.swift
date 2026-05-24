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

/// A compact stacked bar summarising how the user's items are distributed across the SRS stage
/// categories (Apprentice → Burned), shown above the per-category rows in the "All levels" section.
@available(iOS 15.0, *)
class SRSDistributionItem: TableModelItem {
  /// Counts indexed by `SRSStageCategory.rawValue` (apprentice...burned).
  let counts: [Int]
  /// Lifetime review accuracy (0...100), or nil if unknown.
  let accuracy: Double?

  init(counts: [Int], accuracy: Double?) {
    self.counts = counts
    self.accuracy = accuracy
  }

  var cellFactory: TableModelCellFactory {
    .fromDefaultConstructor(cellClass: SRSDistributionCell.self)
  }

  var rowHeight: CGFloat? { accuracy == nil ? 86 : 112 }

  var diffIdentifier: String {
    "srsdist|" + counts.map(String.init).joined(separator: ",")
      + "|" + (accuracy.map { String(Int($0.rounded())) } ?? "-")
  }
}

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

@available(iOS 15.0, *)
class SRSDistributionCell: TableModelCell {
  @TypedModelItem var item: SRSDistributionItem

  private var hostingController: UIHostingController<SRSDistributionView>?

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    selectionStyle = .none
    backgroundColor = TKMStyle.Color.cellBackground
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func update() {
    let view = SRSDistributionView(stages: SRSDistributionView.stages(from: item.counts),
                                   accuracy: item.accuracy)
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
