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
import UIKit

class LessonSettingsViewController: UITableViewController, TKMViewController {
  private var model: TableModel?

  // MARK: - TKMViewController

  var canSwipeToGoBack: Bool { true }

  // MARK: - UIViewController

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.isNavigationBarHidden = false
    rerender()
  }

  private func rerender() {
    let model = MutableTableModel(tableView: tableView)

    model.add(BasicModelItem(style: .value1,
                             title: "Order",
                             subtitle: lessonOrderValueText,
                             accessoryType: .disclosureIndicator) {
        [unowned self] in self.didTapLessonOrder()
      })
    model.add(BasicModelItem(style: .value1,
                             title: "Batch size",
                             subtitle: lessonBatchSizeText,
                             accessoryType: .disclosureIndicator) {
        [unowned self] in self.didTapLessonBatchSize()
      })
    model.add(SwitchModelItem(style: .subtitle,
                              title: "Prioritize current level",
                              subtitle: "Teach items from the current level first",
                              on: Settings.prioritizeCurrentLevel) {
        [unowned self] in
        self.prioritizeCurrentLevelChanged($0)
      })
    model.add(SwitchModelItem(style: .subtitle,
                              title: "Random order",
                              subtitle: "Shuffle lessons instead of ordering by type",
                              on: Settings.randomLessonOrder) { Settings.randomLessonOrder = $0.isOn
      })
    model.add(BasicModelItem(style: .value1,
                             title: "Apprentice limit",
                             subtitle: apprenticeLessonsLimitText,
                             accessoryType: .disclosureIndicator) {
        [unowned self] in self.didTapApprenticeLessonsLimit()
      })
    model.add(SwitchModelItem(style: .subtitle,
                              title: "Show kana-only vocabulary",
                              subtitle: "Include lessons for kana-only vocabulary" +
                                " that were added in May 2023",
                              on: Settings.showKanaOnlyVocab) {
        [unowned self] in
        self.showKanaOnlyVocabChanged($0)
      })
    model.add(SwitchModelItem(style: .subtitle,
                              title: "Allow excluding vocabulary items",
                              subtitle: "Allow excluding vocabulary items from lessons, reviews, etc.",
                              on: Settings.allowExcludeItems) {
        [unowned self] in
        self.allowExcludeVocabChanged($0)
      })

    self.model = model
    model.reloadTable()
  }

  // MARK: - Text rendering

  private var lessonOrderValueText: String {
    var parts = [String]()
    for subjectType in Settings.lessonOrder {
      parts.append(subjectType.description)
    }
    return parts.joined(separator: ", ")
  }

  private var lessonBatchSizeText: String {
    "\(Settings.lessonBatchSize)"
  }

  private var apprenticeLessonsLimitText: String {
    Settings.apprenticeLessonsLimit != Int.max ?
      "\(Settings.apprenticeLessonsLimit)" : "None"
  }

  // MARK: - Switch change handlers

  private func prioritizeCurrentLevelChanged(_ switchView: UISwitch) {
    Settings.prioritizeCurrentLevel = switchView.isOn
  }

  private func showKanaOnlyVocabChanged(_ switchView: UISwitch) {
    Settings.showKanaOnlyVocab = switchView.isOn
  }

  private func allowExcludeVocabChanged(_ switchView: UISwitch) {
    Settings.allowExcludeItems = switchView.isOn
  }

  // MARK: - Tap handlers

  private func didTapLessonOrder() {
    perform(segue: StoryboardSegue.LessonSettings.lessonOrder, sender: self)
  }

  private func didTapLessonBatchSize() {
    navigationController?.pushViewController(makeLessonBatchSizeViewController(), animated: true)
  }

  private func didTapApprenticeLessonsLimit() {
    navigationController?.pushViewController(makeApprenticeLessonLimitViewController(),
                                             animated: true)
  }
}

func makeLessonBatchSizeViewController() -> UIViewController {
  var choices = [ChoiceListScreen<Int>.Choice(label: "1 lesson", value: 1)]
  choices += (2 ... 10).map { ChoiceListScreen<Int>.Choice(label: "\($0) lessons", value: $0) }
  return ChoiceListHostingController(title: "Lesson Batch Size",
                                     helpText: "Set the number of new lessons to be introduced before the quiz session.",
                                     choices: choices, current: Settings.lessonBatchSize,
                                     defaultValue: Settings.$lessonBatchSize.defaultValue) {
    Settings.lessonBatchSize = $0
  }
}

func makeApprenticeLessonLimitViewController() -> UIViewController {
  var choices = [ChoiceListScreen<Int>.Choice(label: "No limit", value: Int.max)]
  choices += stride(from: 25, through: 200, by: 25)
    .map { ChoiceListScreen<Int>.Choice(label: "\($0)", value: $0) }
  return ChoiceListHostingController(title: "Apprentice Lessons Limit",
                                     helpText: "Stop yourself from starting new lessons if you have more than this number of Apprentice-level items already.",
                                     choices: choices, current: Settings.apprenticeLessonsLimit,
                                     defaultValue: Settings.$apprenticeLessonsLimit.defaultValue) {
    Settings.apprenticeLessonsLimit = $0
  }
}
