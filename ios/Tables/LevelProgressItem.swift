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

/// Modern current-level progress: one segmented bar per subject type (radicals / kanji / vocab)
/// showing Guru'd / Apprentice / Lesson / Locked proportions in the brand colour. Replaces the old
/// three-pie-chart cell on iOS 15+ (older systems fall back to `CurrentLevelChartItem`).
@available(iOS 15.0, *)
class LevelProgressItem: TableModelItem {
  let assignments: [TKMAssignment]

  init(currentLevelAssignments: [TKMAssignment]) {
    assignments = currentLevelAssignments
  }

  var cellFactory: TableModelCellFactory {
    .fromDefaultConstructor(cellClass: LevelProgressCell.self)
  }

  var rowHeight: CGFloat? { 128 }

  var diffIdentifier: String {
    var digest = assignments.count
    for assignment in assignments {
      digest = digest &* 31 &+ Int(assignment.subjectType.rawValue) &* 11
        &+ Int(assignment.srsStageNumber)
    }
    return "level-\(digest)"
  }
}

@available(iOS 15.0, *)
struct LevelProgressView: View {
  struct Segment: Identifiable {
    let id = UUID()
    let value: Int
    let color: Color
  }

  struct Row: Identifiable {
    let id = UUID()
    let label: String
    let passed: Int
    let total: Int
    let segments: [Segment]
  }

  let rows: [Row]

  var body: some View {
    VStack(spacing: 11) {
      ForEach(rows) { row in
        VStack(spacing: 4) {
          HStack(alignment: .firstTextBaseline) {
            Text(row.label)
              .font(.caption.weight(.semibold))
            Spacer()
            Text("\(row.passed)/\(row.total) passed")
              .font(.caption2)
              .foregroundStyle(.secondary)
              .monospacedDigit()
          }
          GeometryReader { geo in
            HStack(spacing: row.total > 0 ? 1 : 0) {
              ForEach(row.segments) { seg in
                seg.color
                  .frame(width: width(for: seg.value, total: row.total, in: geo.size.width))
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 10)
            .background(Color.secondary.opacity(0.15))
            .clipShape(Capsule())
          }
          .frame(height: 10)
        }
      }
    }
    .padding(.vertical, 8)
  }

  private func width(for value: Int, total: Int, in fullWidth: CGFloat) -> CGFloat {
    guard total > 0, value > 0 else { return 0 }
    return max(fullWidth * CGFloat(value) / CGFloat(total) - 1, 0)
  }
}

@available(iOS 15.0, *)
extension LevelProgressView {
  /// Builds the radicals / kanji / vocabulary progress rows from a level's assignments. Shared by
  /// the dashboard table cell and the SwiftUI dashboard so the two stay in lock-step.
  static func rows(from assignments: [TKMAssignment]) -> [Row] {
    [makeRow(label: "Radicals", type: .radical, assignments: assignments),
     makeRow(label: "Kanji", type: .kanji, assignments: assignments),
     makeRow(label: "Vocabulary", type: .vocabulary, assignments: assignments)]
  }

  private static func makeRow(label: String, type: TKMSubject.TypeEnum,
                              assignments: [TKMAssignment]) -> Row {
    var locked = 0, lesson = 0, apprentice = 0, guru = 0
    for assignment in assignments {
      guard assignment.hasSubjectType, assignment.subjectType == type else { continue }
      if assignment.isLessonStage {
        lesson += 1
      } else if !assignment.hasSrsStageNumber {
        locked += 1
      } else if assignment.srsStage < .guru1 {
        apprentice += 1
      } else {
        guru += 1
      }
    }

    let base = TKMStyle.color2(forSubjectType: type)
    // Left-to-right: most progressed first.
    let segments = [
      Segment(value: guru, color: Color(uiColor: base)),
      Segment(value: apprentice, color: Color(uiColor: base).opacity(0.5)),
      Segment(value: lesson, color: Color(uiColor: TKMStyle.Color.grey66)),
      Segment(value: locked, color: Color(uiColor: TKMStyle.Color.grey80)),
    ]
    return Row(label: label, passed: guru,
               total: locked + lesson + apprentice + guru, segments: segments)
  }
}

@available(iOS 15.0, *)
class LevelProgressCell: TableModelCell {
  @TypedModelItem var item: LevelProgressItem

  private var hostingController: UIHostingController<LevelProgressView>?

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
    let view = LevelProgressView(rows: LevelProgressView.rows(from: item.assignments))
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
