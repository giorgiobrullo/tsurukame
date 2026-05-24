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

// Generic SwiftUI single-choice list, replacing the UIKit SettingChoiceListViewController. The
// `make*ViewController()` setting factories return one of these hosting controllers, so their call
// sites are unchanged.

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

@available(iOS 15.0, *)
final class ChoiceListHostingController<Value: Equatable>: UIHostingController<ChoiceListScreen<Value>>,
  TKMViewController {
  private let onSet: (Value) -> Void

  var canSwipeToGoBack: Bool { true }

  init(title: String, helpText: String? = nil, choices: [ChoiceListScreen<Value>.Choice],
       current: Value, defaultValue: Value?, set: @escaping (Value) -> Void) {
    onSet = set
    super.init(rootView: ChoiceListScreen(choices: choices, current: current,
                                          defaultValue: defaultValue, helpText: helpText,
                                          onSelect: { _ in }))
    self.title = title
    rootView = ChoiceListScreen(choices: choices, current: current, defaultValue: defaultValue,
                                helpText: helpText, onSelect: { [weak self] in self?.choose($0) })
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.isNavigationBarHidden = false
  }

  private func choose(_ value: Value) {
    onSet(value)
    navigationController?.popViewController(animated: true)
  }
}

/// Builds a choice list for an enum setting (labels from `description`).
@available(iOS 15.0, *)
func makeEnumChoiceList<T>(title: String, current: T, defaultValue: T,
                           set: @escaping (T) -> Void) -> UIViewController
  where T: CaseIterable & CustomStringConvertible & Equatable {
  let choices = Array(T.allCases)
    .map { ChoiceListScreen<T>.Choice(label: $0.description, value: $0) }
  return ChoiceListHostingController(title: title, choices: choices, current: current,
                                     defaultValue: defaultValue, set: set)
}
