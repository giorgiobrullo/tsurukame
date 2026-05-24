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
import WaniKaniAPI

/// Reverse practice (#803, safe standalone form): shows the English meaning and asks you to recall
/// the Japanese, then reveals it. A flashcard, separate from the SRS review engine, so it never
/// affects scheduling. (The full typed-answer-in-reviews version would need answer-checker
/// changes.)
class ReversePracticeViewController: UIViewController, TKMViewController {
  private var services: TKMServices!
  private var subjects: [TKMSubject] = []
  private var index = 0
  private var revealed = false

  private let progressLabel = UILabel()
  private let promptLabel = UILabel()
  private let typeChip = UILabel()
  private let wordLabel = UILabel()
  private let readingLabel = UILabel()
  private let answerStack = UIStackView()
  private let actionButton = UIButton(type: .system)

  var canSwipeToGoBack: Bool { true }

  func setup(services: TKMServices) { self.services = services }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Reverse"
    view.backgroundColor = TKMStyle.Color.background
    buildSubjects()
    buildUI()
    showCurrent()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.isNavigationBarHidden = false
  }

  private func buildSubjects() {
    let client = services.localCachingClient!
    func recallable(_ assignments: [TKMAssignment]) -> [TKMSubject] {
      assignments.filter { $0.isReviewStage }
        .compactMap { client.getSubject(id: $0.subjectID) }
        // Kanji and vocab have a meaning to prompt with and a reading to recall.
        .filter { ($0.hasKanji || $0.hasVocabulary) && !$0.readings.isEmpty }
    }
    var found = recallable(client.getAssignmentsAtUsersCurrentLevel())
    if found.isEmpty { found = recallable(client.getAllAssignments()) }
    subjects = found.shuffled()
  }

  private func buildUI() {
    progressLabel.font = .systemFont(ofSize: 13, weight: .semibold)
    progressLabel.textColor = .secondaryLabel
    progressLabel.textAlignment = .center

    typeChip.font = .systemFont(ofSize: 12, weight: .bold)
    typeChip.textColor = .white
    typeChip.textAlignment = .center
    typeChip.layer.cornerRadius = 6
    typeChip.clipsToBounds = true

    promptLabel.font = .systemFont(ofSize: 30, weight: .semibold)
    promptLabel.textColor = TKMStyle.Color.label
    promptLabel.textAlignment = .center
    promptLabel.numberOfLines = 0

    wordLabel.font = UIFont(name: TKMStyle.japaneseFontName, size: 48)
    wordLabel.textColor = TKMStyle.Color.label
    wordLabel.textAlignment = .center
    readingLabel.font = UIFont(name: TKMStyle.japaneseFontName, size: 24)
    readingLabel.textColor = .secondaryLabel
    readingLabel.textAlignment = .center

    answerStack.axis = .vertical
    answerStack.spacing = 8
    answerStack.alignment = .center
    [wordLabel, readingLabel].forEach { answerStack.addArrangedSubview($0) }
    answerStack.isHidden = true

    actionButton.addAction(for: .touchUpInside) { [unowned self] in self.actionTapped() }

    let typeRow = UIStackView(arrangedSubviews: [typeChip])
    typeRow.axis = .horizontal
    typeRow.alignment = .center

    let stack = UIStackView(arrangedSubviews: [progressLabel, typeRow, promptLabel, answerStack])
    stack.axis = .vertical
    stack.alignment = .center
    stack.spacing = 22
    stack.setCustomSpacing(8, after: progressLabel)
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    actionButton.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(actionButton)

    typeChip.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      typeChip.heightAnchor.constraint(equalToConstant: 22),
      typeChip.widthAnchor.constraint(greaterThanOrEqualToConstant: 64),
      stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -30),
      stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
      actionButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      actionButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                                           constant: -24),
    ])
  }

  private func showCurrent() {
    guard !subjects.isEmpty else {
      progressLabel.text = "Nothing to practice yet"
      promptLabel.text = ""
      typeChip.isHidden = true
      actionButton.isHidden = true
      return
    }
    let subject = subjects[index]
    progressLabel.text = "\(index + 1) / \(subjects.count)"
    promptLabel.text = subject.commaSeparatedMeanings(showOldMnemonic: Settings.showOldMnemonic)
    typeChip.text = subject.hasKanji ? " Kanji " : " Vocab "
    typeChip.backgroundColor = subject.hasKanji ? TKMStyle.kanjiColor2 : TKMStyle.vocabularyColor2
    wordLabel.text = subject.japanese
    readingLabel.text = subject.readings
      .map { $0.displayText(useKatakanaForOnyomi: Settings.useKatakanaForOnyomi) }
      .joined(separator: ", ")

    revealed = false
    answerStack.isHidden = true
    updateActionButton()
  }

  private func updateActionButton() {
    actionButton.setTitle(revealed ? "  Next" : "  Reveal", for: .normal)
    actionButton.setImage(UIImage(systemName: revealed ? "arrow.right" : "eye"), for: .normal)
    actionButton.tintColor = TKMStyle.defaultTintColor
    actionButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
  }

  private func actionTapped() {
    if revealed {
      index = (index + 1) % subjects.count
      showCurrent()
    } else {
      revealed = true
      answerStack.isHidden = false
      updateActionButton()
      // Play the audio for vocab when revealing, as extra reinforcement.
      if subjects[index].hasVocabulary, !subjects[index].vocabulary.audio.isEmpty {
        services.audio.play(subjectID: subjects[index].id, delegate: nil)
      }
    }
  }
}
