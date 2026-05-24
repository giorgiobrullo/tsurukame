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

func makeFontSizeViewController() -> UIViewController {
  var choices = [ChoiceListScreen<Float>.Choice]()
  for size in stride(from: 1.0, through: 2.5, by: 0.25) {
    choices.append(.init(label: "\(Int((size * 100).rounded()))%", value: Float(size)))
  }
  return ChoiceListHostingController(title: "Font Size", choices: choices,
                                     current: Settings.fontSize,
                                     defaultValue: Settings.$fontSize.defaultValue) {
    Settings.fontSize = $0
  }
}

func makeReviewBatchSizeViewController() -> UIViewController {
  let name = "Reviews Between Meaning & Reading"
  let description =
    "The \"\(name)\" setting is ONLY used when \"back-to-back\" reviews are disabled.\n\n" +
    "When \"back-to-back\" reviews are disabled, you might be asked to review the meaning of an item and then " +
    "later after reviewing some other items, be asked to review the reading of that item. \nThe \"\(name)\" setting " +
    "controls the number of different review items you can encounter between reviewing the reading and " +
    "meaning for a given item."
  let choices = (3 ... 10).map { ChoiceListScreen<Int>.Choice(label: "\($0) reviews", value: $0) }
  return ChoiceListHostingController(title: name, helpText: description, choices: choices,
                                     current: Settings.reviewBatchSize,
                                     defaultValue: Settings.$reviewBatchSize.defaultValue) {
    Settings.reviewBatchSize = $0
  }
}

func makeReviewItemsLimitViewController() -> UIViewController {
  let choices = [5, 10, 15, 20, 25, 30, 50, 75, 100]
    .map { ChoiceListScreen<Int>.Choice(label: "\($0) reviews", value: $0) }
  return ChoiceListHostingController(title: "Review Batch Size",
                                     helpText: "Set the number of items to review in a session.",
                                     choices: choices, current: Settings.reviewItemsLimit,
                                     defaultValue: Settings.$reviewItemsLimit.defaultValue) {
    Settings.reviewItemsLimit = $0
  }
}

func makeLeechThresholdViewController() -> UIViewController {
  var choices = [ChoiceListScreen<Float>.Choice]()
  for threshold in stride(from: 1.0, through: 5.0, by: 0.25) {
    choices.append(.init(label: "\(threshold)", value: Float(threshold)))
  }
  return ChoiceListHostingController(title: "Leech Threshold",
                                     helpText: "Leeches are the items that you regularly get wrong. The lower the leech threshold value, the more items will be considered leeches. Leeches are considered a leech if (incorrect / currentStreak^1.5 >= threshold) is true.",
                                     choices: choices, current: Settings.leechThreshold,
                                     defaultValue: Settings.$leechThreshold.defaultValue) {
    Settings.leechThreshold = $0
  }
}

func makeReviewOrderViewController() -> UIViewController {
  makeEnumChoiceList(title: "Review Order", current: Settings.reviewOrder,
                     defaultValue: Settings.$reviewOrder.defaultValue) { Settings.reviewOrder = $0 }
}

func makeTaskOrderViewController() -> UIViewController {
  let choices = [
    ChoiceListScreen<Bool>.Choice(label: "Meaning then Reading", value: true),
    ChoiceListScreen<Bool>.Choice(label: "Reading then Meaning", value: false),
  ]
  return ChoiceListHostingController(title: "Back-to-back Order", choices: choices,
                                     current: Settings.meaningFirst,
                                     defaultValue: Settings.$meaningFirst.defaultValue) {
    Settings.meaningFirst = $0
  }
}

func makeAnkiModeTaskTypeViewController() -> UIViewController {
  makeEnumChoiceList(title: "Anki Mode Applies To", current: Settings.ankiModeTaskType,
                     defaultValue: Settings.$ankiModeTaskType.defaultValue) {
    Settings.ankiModeTaskType = $0
  }
}
