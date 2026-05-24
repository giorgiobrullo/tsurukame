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
import WaniKaniAPI

class ReviewSummaryViewController: UITableViewController, SubjectDelegate {
  private var services: TKMServices!
  private var model: TableModel!
  private var incorrectItems: [ReviewItem] = []

  func setup(services: TKMServices, items: [ReviewItem]) {
    self.services = services

    let currentLevel = services.localCachingClient.getUserInfo()!.level
    var incorrectItemsByLevel = [Int32: [ReviewItem]]()
    var correct = 0
    for item in items {
      if !item.answer.meaningWrong, !item.answer.readingWrong {
        correct += 1
        continue
      }
      incorrectItemsByLevel[item.assignment.level, default: []].append(item)
    }
    incorrectItems = incorrectItemsByLevel.values.flatMap { $0 }

    let model = MutableTableModel(tableView: tableView)

    // Summary section.
    var summaryText: String
    if items.isEmpty {
      summaryText = "0%"
    } else {
      summaryText =
        "\(Int(Double(correct) / Double(items.count) * 100.0))% (\(correct)/\(items.count))"
    }
    model.add(section: "Summary")
    model.add(BasicModelItem(style: .value1, title: "Correct answers", subtitle: summaryText))

    // Immediately re-review the items you got wrong (#335), as a no-SRS practice round.
    if !incorrectItems.isEmpty {
      let reReviewItem = BasicModelItem(style: .value1, title: "Re-review incorrect items",
                                        subtitle: "\(incorrectItems.count)",
                                        accessoryType: .disclosureIndicator) { [unowned self] in
        self.startReReview()
      }
      reReviewItem.textColor = TKMStyle.defaultTintColor
      reReviewItem.image = UIImage(systemName: "arrow.clockwise")
      reReviewItem.imageTintColor = TKMStyle.defaultTintColor
      model.add(reReviewItem)
    }

    // Add a section for each level.
    let incorrectItemLevels = incorrectItemsByLevel.keys.sorted { a, b -> Bool in
      b < a
    }
    for level in incorrectItemLevels {
      if level == currentLevel {
        model.add(section: "Current level (\(level))")
      } else {
        model.add(section: "Level \(level)")
      }

      for item in incorrectItemsByLevel[level]! {
        var subject = item.subject
        if subject == nil {
          subject = services.localCachingClient.getSubject(id: item.assignment.subjectID)
        }
        guard let subject = subject else {
          continue
        }

        model.add(SubjectModelItem(subject: subject, delegate: self, assignment: nil,
                                   readingWrong: item.answer.readingWrong,
                                   meaningWrong: item.answer.meaningWrong))
      }
    }
    self.model = model
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.isNavigationBarHidden = false
  }

  @IBAction private func doneClicked() {
    navigationController?.popToRootViewController(animated: true)
  }

  private func startReReview() {
    // Fresh ReviewItems (reset answer state) so the re-review starts clean. Practice session, so it
    // doesn't touch SRS — these were already marked in the main session.
    let freshItems = incorrectItems.map { ReviewItem(assignment: $0.assignment, subject: $0.subject)
    }
    guard !freshItems.isEmpty else { return }
    let vc = SwiftUIReviewHostingController(services: services, items: freshItems.shuffled(),
                                            isPracticeSession: true)
    navigationController?.pushViewController(vc, animated: true)
  }

  override var canBecomeFirstResponder: Bool {
    true
  }

  override var keyCommands: [UIKeyCommand]? {
    [
      UIKeyCommand(input: "\r",
                   modifierFlags: [],
                   action: #selector(doneClicked),
                   discoverabilityTitle: "Dismiss review session results"),
    ]
  }

  // MARK: - SubjectDelegate

  func didTapSubject(_ subject: TKMSubject) {
    navigationController?.pushViewController(SubjectDetailHostingController(services: services,
                                                                            subject: subject),
                                             animated: true)
  }
}
