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

// SwiftUI rewrites of the listening- and reverse-practice flashcard modes. Self-contained: no SRS
// impact, just a reveal-and-advance flashcard over the current level's items.

// MARK: - Listening practice

@available(iOS 15.0, *)
struct ListeningPracticeScreen: View {
  let services: TKMServices
  let subjects: [TKMSubject]

  @State private var index = 0
  @State private var revealed = false

  var body: some View {
    VStack(spacing: 28) {
      if subjects.isEmpty {
        Text("No vocabulary with audio yet").foregroundStyle(.secondary)
      } else {
        Text("\(index + 1) / \(subjects.count)")
          .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        Button(action: play) {
          Image(systemName: "speaker.wave.3.fill")
            .font(.system(size: 44)).foregroundStyle(.white)
            .frame(width: 100, height: 100)
            .background(Color(uiColor: TKMStyle.radicalColor2)).clipShape(Circle())
        }
        if revealed {
          VStack(spacing: 8) {
            Text(subjects[index].japanese)
              .font(.custom(TKMStyle.japaneseFontName, size: 44)).foregroundStyle(Color.tkmLabel)
            Text(reading).font(.custom(TKMStyle.japaneseFontName, size: 22))
              .foregroundStyle(.secondary)
            Text(meaning).font(.system(size: 20, weight: .medium)).foregroundStyle(Color.tkmLabel)
              .multilineTextAlignment(.center)
          }
        }
        Button(revealed ? "Next" : "Reveal") {
          if revealed { next() } else { revealed = true }
        }
        .font(.headline).buttonStyle(.borderedProminent)
        .tint(Color(uiColor: TKMStyle.radicalColor2))
      }
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.tkmBackground.ignoresSafeArea())
    .onAppear { if !subjects.isEmpty { play() } }
  }

  private var reading: String {
    subjects[index].readings
      .map { $0.displayText(useKatakanaForOnyomi: Settings.useKatakanaForOnyomi) }
      .joined(separator: ", ")
  }

  private var meaning: String {
    subjects[index].commaSeparatedMeanings(showOldMnemonic: Settings.showOldMnemonic)
  }

  private func play() { services.audio.play(subjectID: subjects[index].id, delegate: nil) }

  private func next() {
    index = (index + 1) % subjects.count
    revealed = false
    play()
  }
}

// MARK: - Reverse practice

@available(iOS 15.0, *)
struct ReversePracticeScreen: View {
  let services: TKMServices
  let subjects: [TKMSubject]

  @State private var index = 0
  @State private var revealed = false

  var body: some View {
    VStack(spacing: 22) {
      if subjects.isEmpty {
        Text("Nothing to practice yet").foregroundStyle(.secondary)
      } else {
        Text("\(index + 1) / \(subjects.count)")
          .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        Text(subjects[index].hasKanji ? "Kanji" : "Vocab")
          .font(.caption.weight(.bold)).foregroundStyle(.white)
          .padding(.horizontal, 10).padding(.vertical, 4)
          .background(Color(uiColor: subjects[index].hasKanji ? TKMStyle.kanjiColor2
              : TKMStyle.vocabularyColor2))
          .clipShape(Capsule())
        Text(meaning)
          .font(.system(size: 30, weight: .semibold)).foregroundStyle(Color.tkmLabel)
          .multilineTextAlignment(.center)
        if revealed {
          VStack(spacing: 8) {
            Text(subjects[index].japanese)
              .font(.custom(TKMStyle.japaneseFontName, size: 48)).foregroundStyle(Color.tkmLabel)
            Text(reading).font(.custom(TKMStyle.japaneseFontName, size: 24))
              .foregroundStyle(.secondary)
          }
        }
        Button(revealed ? "Next" : "Reveal") {
          if revealed { next() } else { reveal() }
        }
        .font(.headline).buttonStyle(.borderedProminent)
        .tint(Color(uiColor: TKMStyle.radicalColor2))
      }
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.tkmBackground.ignoresSafeArea())
  }

  private var reading: String {
    subjects[index].readings
      .map { $0.displayText(useKatakanaForOnyomi: Settings.useKatakanaForOnyomi) }
      .joined(separator: ", ")
  }

  private var meaning: String {
    subjects[index].commaSeparatedMeanings(showOldMnemonic: Settings.showOldMnemonic)
  }

  private func reveal() {
    revealed = true
    if subjects[index].hasVocabulary, !subjects[index].vocabulary.audio.isEmpty {
      services.audio.play(subjectID: subjects[index].id, delegate: nil)
    }
  }

  private func next() {
    index = (index + 1) % subjects.count
    revealed = false
  }
}
