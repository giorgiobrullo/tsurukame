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

// SwiftUI rewrite of ReviewSummaryViewController: the end-of-session results — accuracy, the wrong
// items grouped by level (reusing SubjectRow), and a re-review shortcut.

@available(iOS 15.0, *)
struct ReviewSummaryScreen: View {
  struct LevelGroup: Identifiable {
    let id = UUID()
    let title: String
    let rows: [SubjectRowData]
  }

  let correct: Int
  let total: Int
  let incorrectCount: Int
  let groups: [LevelGroup]
  let onReReview: () -> Void
  let onTapSubject: (TKMSubject) -> Void

  private var percentText: String {
    total == 0 ? "0%" : "\(Int(Double(correct) / Double(total) * 100))% (\(correct)/\(total))"
  }

  var body: some View {
    List {
      Section("Summary") {
        HStack {
          Text("Correct answers")
          Spacer()
          Text(percentText).foregroundStyle(.secondary).monospacedDigit()
        }
        if incorrectCount > 0 {
          Button(action: onReReview) {
            Label("Re-review incorrect items (\(incorrectCount))", systemImage: "arrow.clockwise")
              .foregroundStyle(Color.tkmTint)
          }
        }
      }

      ForEach(groups) { group in
        Section(group.title) {
          ForEach(group.rows) { row in
            SubjectRow(data: row, onTap: onTapSubject)
          }
        }
      }
    }
  }
}

@available(iOS 15.0, *)
final class ReviewSummaryHostingController: UIHostingController<ReviewSummaryScreen>,
  TKMViewController {
  private let services: TKMServices
  private let incorrectItems: [ReviewItem]

  var canSwipeToGoBack: Bool { true }

  init(services: TKMServices, items: [ReviewItem]) {
    self.services = services

    // Split into correct / incorrect-by-level, mirroring ReviewSummaryViewController.
    let currentLevel = services.localCachingClient.getUserInfo()?.level ?? 0
    var incorrectByLevel = [Int32: [ReviewItem]]()
    var correct = 0
    for item in items {
      if !item.answer.meaningWrong, !item.answer.readingWrong {
        correct += 1
      } else {
        incorrectByLevel[item.assignment.level, default: []].append(item)
      }
    }
    incorrectItems = incorrectByLevel.values.flatMap { $0 }

    var groups = [ReviewSummaryScreen.LevelGroup]()
    for level in incorrectByLevel.keys.sorted(by: >) {
      let rows = incorrectByLevel[level]!.compactMap { item -> SubjectRowData? in
        let subject = item.subject
          ?? services.localCachingClient.getSubject(id: item.assignment.subjectID)
        guard let subject = subject else { return nil }
        return SubjectRowData(id: subject.id, subject: subject, assignment: nil)
      }
      let title = level == currentLevel ? "Current level (\(level))" : "Level \(level)"
      groups.append(.init(title: title, rows: rows))
    }

    super.init(rootView: ReviewSummaryScreen(correct: correct, total: items.count,
                                             incorrectCount: incorrectItems.count, groups: groups,
                                             onReReview: {}, onTapSubject: { _ in }))
    title = "Reviews"
    rootView = ReviewSummaryScreen(correct: correct, total: items.count,
                                   incorrectCount: incorrectItems.count, groups: groups,
                                   onReReview: { [weak self] in self?.reReview() },
                                   onTapSubject: { [weak self] in self?.openDetail($0) })
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self,
                                                        action: #selector(done))
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.isNavigationBarHidden = false
  }

  @objc private func done() {
    navigationController?.popToRootViewController(animated: true)
  }

  private func reReview() {
    // Fresh items (reset answer state); a practice round so it doesn't re-touch SRS.
    let freshItems = incorrectItems.map { ReviewItem(assignment: $0.assignment, subject: $0.subject)
    }
    guard !freshItems.isEmpty else { return }
    let vc = SwiftUIReviewHostingController(services: services, items: freshItems.shuffled(),
                                            isPracticeSession: true)
    navigationController?.pushViewController(vc, animated: true)
  }

  private func openDetail(_ subject: TKMSubject) {
    navigationController?.pushViewController(SubjectDetailHostingController(services: services,
                                                                            subject: subject),
                                             animated: true)
  }
}
