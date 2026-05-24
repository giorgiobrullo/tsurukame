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
