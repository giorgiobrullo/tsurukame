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

// Generic SwiftUI single-choice list, used as NavigationStack destinations for the settings
// pickers (and the dashboard's review-order shortcut).

@available(iOS 15.0, *)
struct ChoiceListScreen<Value: Equatable>: View {
  struct Choice: Identifiable {
    let id = UUID()
    let label: String
    let value: Value
  }

  let choices: [Choice]
  let current: Value
  let defaultValue: Value?
  let helpText: String?
  let onSelect: (Value) -> Void

  var body: some View {
    List {
      Section {
        ForEach(choices) { choice in
          Button { onSelect(choice.value) } label: {
            HStack {
              Text(label(for: choice)).foregroundStyle(Color.tkmLabel)
              Spacer()
              if choice.value == current {
                Image(systemName: "checkmark").foregroundStyle(Color.tkmTint)
              }
            }
          }
        }
      } footer: {
        if let helpText = helpText { Text(helpText) }
      }
    }
  }

  private func label(for choice: Choice) -> String {
    if let defaultValue = defaultValue, choice.value == defaultValue {
      return "\(choice.label) (default)"
    }
    return choice.label
  }
}
