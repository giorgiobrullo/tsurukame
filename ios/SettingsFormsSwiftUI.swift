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

// SwiftUI rewrites of the larger settings forms: Lessons, Reviews and Subject info. Value rows that
// pick from a list still push the existing UIKit `SettingChoiceListViewController` pickers (via
// `SettingsNavigator`); everything else is native toggles bound through `SettingsStore`.

// MARK: - Lessons

@available(iOS 15.0, *)
struct LessonSettingsScreen: View {
  let nav: SettingsNavigator
  @StateObject private var store = SettingsStore()

  private var orderText: String {
    Settings.lessonOrder.map { $0.description }.joined(separator: ", ")
  }

  private var apprenticeLimitText: String {
    Settings.apprenticeLessonsLimit != Int.max ? "\(Settings.apprenticeLessonsLimit)" : "None"
  }

  var body: some View {
    List {
      Button { nav.openLessonOrder() } label: {
        DetailDisclosureRow(title: "Order", value: orderText)
      }
      Button { nav.openLessonBatchSize() } label: {
        DetailDisclosureRow(title: "Batch size", value: "\(Settings.lessonBatchSize)")
      }
      Toggle(isOn: store
        .bind(Settings.prioritizeCurrentLevel) { Settings.prioritizeCurrentLevel = $0 }) {
          SubtitleLabel("Prioritize current level", "Teach items from the current level first")
        }
      Toggle(isOn: store.bind(Settings.randomLessonOrder) { Settings.randomLessonOrder = $0 }) {
        SubtitleLabel("Random order", "Shuffle lessons instead of ordering by type")
      }
      Button { nav.openApprenticeLimit() } label: {
        DetailDisclosureRow(title: "Apprentice limit", value: apprenticeLimitText)
      }
      Toggle(isOn: store.bind(Settings.showKanaOnlyVocab) { Settings.showKanaOnlyVocab = $0 }) {
        SubtitleLabel("Show kana-only vocabulary",
                      "Include lessons for kana-only vocabulary that were added in May 2023")
      }
      Toggle(isOn: store.bind(Settings.allowExcludeItems) { Settings.allowExcludeItems = $0 }) {
        SubtitleLabel("Allow excluding vocabulary items",
                      "Allow excluding vocabulary items from lessons, reviews, etc.")
      }
    }
    .onAppear { store.refresh() }
  }
}

// MARK: - Reviews

@available(iOS 15.0, *)
struct ReviewSettingsScreen: View {
  let nav: SettingsNavigator
  @StateObject private var store = SettingsStore()

  var body: some View {
    List {
      Section {
        Toggle(isOn: store.bind(Settings.useSwiftUIReviews) { Settings.useSwiftUIReviews = $0 }) {
          SubtitleLabel("SwiftUI reviews (beta)",
                        "Native review engine, in progress. Exercised via Self-study current level.")
        }
      } footer: {
        Text("The SwiftUI review engine is an in-progress rewrite. While on, Self-study uses it (no SRS impact); the classic engine is still used everywhere else.")
      }

      Section {
        Toggle(isOn: store
          .bind(Settings.reviewItemsLimitEnabled) { Settings.reviewItemsLimitEnabled = $0 }) {
            SubtitleLabel("Review items in batches", "Limit the number of items in review sessions")
          }
        if Settings.reviewItemsLimitEnabled {
          Button { nav.openReviewItemsLimit() } label: {
            DetailDisclosureRow(title: "Batch size", value: Settings.reviewItemsLimit.description)
          }
        }
        Button { nav.openLeechThreshold() } label: {
          DetailDisclosureRow(title: "Leech threshold", value: Settings.leechThreshold.description)
        }
      }

      Section("Order") {
        Button { nav.openReviewOrder() } label: {
          DetailDisclosureRow(title: "Order", value: Settings.reviewOrder.description)
        }
        Toggle(isOn: store
          .bind(Settings.groupMeaningReading) { Settings.groupMeaningReading = $0 }) {
            SubtitleLabel("Back-to-back", "Group meaning and reading together")
          }
        if Settings.groupMeaningReading {
          Button { nav.openTaskOrder() } label: {
            DetailDisclosureRow(title: "Back-to-back order",
                                value: Settings.meaningFirst ? "Meaning first" : "Reading first")
          }
        } else {
          Button { nav.openReviewBatchSize() } label: {
            DetailDisclosureRow(title: "Reviews between meaning & reading",
                                value: Settings.reviewBatchSize.description)
          }
        }
      }

      Section("Display") {
        toggle("Show minutes for next level-up review", nil,
               Settings.showMinutesForNextLevelUpReview) {
          Settings.showMinutesForNextLevelUpReview = $0
        }
      }

      Section("Answers & marking") {
        Toggle(isOn: Binding(get: { Settings.autoSwitchKeyboard }, set: { on in
          if on, AnswerTextField.japaneseTextInputMode == nil {
            nav.showNoJapaneseKeyboardAlert()
            store.refresh()
          } else {
            Settings.autoSwitchKeyboard = on
            store.refresh()
          }
        })) {
          SubtitleLabel("Switch to Japanese keyboard",
                        "Automatically switch to a Japanese keyboard to type reading answers")
        }
        toggle("Reveal answer automatically", nil, Settings.showAnswerImmediately) {
          Settings.showAnswerImmediately = $0
        }
        toggle("Reveal full answer", "Instead of hiding behind a 'Show more information' button",
               Settings.showFullAnswer) { Settings.showFullAnswer = $0 }
        toggle("Exact match", "Requires typing in answers exactly correct",
               Settings.exactMatch) { Settings.exactMatch = $0 }
        toggle("Allow cheating", "Ignore Typos and Add Synonym",
               Settings.enableCheats) { Settings.enableCheats = $0 }
        toggle("Allow skipping", nil, Settings.allowSkippingReviews) {
          Settings.allowSkippingReviews = $0
        }
        toggle("Minimize review penalty",
               "Treat reviews answered incorrect multiple times as if answered incorrect once",
               Settings.minimizeReviewPenalty) { Settings.minimizeReviewPenalty = $0 }
      }

      Section("Animations") {
        toggle("Particle explosion", nil, Settings.animateParticleExplosion) {
          Settings.animateParticleExplosion = $0
        }
        toggle("Level up popup", nil, Settings.animateLevelUpPopup) {
          Settings.animateLevelUpPopup = $0
        }
        toggle("+1", nil, Settings.animatePlusOne) { Settings.animatePlusOne = $0 }
      }
    }
    .onAppear { store.refresh() }
  }

  /// A toggle bound through the store, with an optional grey subtitle.
  private func toggle(_ title: String, _ subtitle: String?,
                      _ get: @autoclosure @escaping () -> Bool,
                      _ set: @escaping (Bool) -> Void) -> some View {
    Toggle(isOn: store.bind(get(), set)) {
      if let subtitle = subtitle {
        SubtitleLabel(title, subtitle)
      } else {
        Text(title)
      }
    }
  }
}

// MARK: - Subject info

@available(iOS 15.0, *)
struct SubjectDetailsSettingsScreen: View {
  @StateObject private var store = SettingsStore()

  var body: some View {
    List {
      toggle("Use Katakana for Onyomi",
             "Show Onyomi kanji readings in Katakana instead of Hiragana",
             Settings.useKatakanaForOnyomi) { Settings.useKatakanaForOnyomi = $0 }
      toggle("Show all kanji readings", "Primary reading(s) will be shown in bold",
             Settings.showAllReadings) { Settings.showAllReadings = $0 }
      toggle("Show stats section", "Level, SRS stage, and more",
             Settings.showStatsSection) { Settings.showStatsSection = $0 }
      toggle("Show old mnemonics", "Include radical mnemonics removed in 2018",
             Settings.showOldMnemonic) { Settings.showOldMnemonic = $0 }
      toggle("Blur context sentences", nil,
             Settings.blurContextSentences) { Settings.blurContextSentences = $0 }
      toggle("Show artwork by @AmandaBear",
             "Mnemonic Artwork for Radical Levels 1-10 and Kanji Levels 1-7",
             Settings.showArtwork) { Settings.showArtwork = $0 }
      toggle("Show prior level graph until fully completed",
             "When you finish the kanji for a given level, keep showing that level's completion graph until all radicals, kanji, and vocabulary have gotten to Guru or higher",
             Settings.showPreviousLevelGraph) { Settings.showPreviousLevelGraph = $0 }
      toggle("Skip Kanji readings",
             "Kanji have meanings and readings. When this setting is enabled, you will not be quizzed about Kanji readings during lessons and review sessions.",
             Settings.skipKanjiReadings) { Settings.skipKanjiReadings = $0 }
      toggle("Show visually similar kanji above current level",
             "When this setting is enabled, the Visually Similar Kanji section will show items above your current level. When this is disabled, only visually similar items at or below your current level will be shown.",
             Settings.showSimilarKanjiAboveLevel) { Settings.showSimilarKanjiAboveLevel = $0 }
    }
  }

  private func toggle(_ title: String, _ subtitle: String?,
                      _ get: @autoclosure @escaping () -> Bool,
                      _ set: @escaping (Bool) -> Void) -> some View {
    Toggle(isOn: store.bind(get(), set)) {
      if let subtitle = subtitle {
        SubtitleLabel(title, subtitle)
      } else {
        Text(title)
      }
    }
  }
}
