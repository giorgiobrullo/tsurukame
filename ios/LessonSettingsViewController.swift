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
