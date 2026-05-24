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

/// Listening practice (#322): a self-contained flashcard mode that plays a vocabulary item's audio
/// and lets you reveal the word, reading and meaning. Deliberately separate from the review engine,
/// so it never affects SRS.
class ListeningPracticeViewController: UIViewController, TKMViewController {
  private var services: TKMServices!
  private var subjects: [TKMSubject] = []
  private var index = 0
  private var revealed = false

  private let progressLabel = UILabel()
  private let playButton = UIButton(type: .system)
  private let wordLabel = UILabel()
  private let readingLabel = UILabel()
  private let meaningLabel = UILabel()
  private let answerStack = UIStackView()
  private let actionButton = UIButton(type: .system)

  var canSwipeToGoBack: Bool { true }

  func setup(services: TKMServices) { self.services = services }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Listening"
    view.backgroundColor = TKMStyle.Color.background
    buildSubjects()
    buildUI()
    showCurrent(playAudio: false)
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    if !subjects.isEmpty { playAudio() }
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.isNavigationBarHidden = false
  }

  private func buildSubjects() {
    let client = services.localCachingClient!
    func vocabWithAudio(_ assignments: [TKMAssignment]) -> [TKMSubject] {
      assignments.filter { $0.isReviewStage }
        .compactMap { client.getSubject(id: $0.subjectID) }
        .filter { $0.hasVocabulary && !$0.vocabulary.audio.isEmpty }
    }
    var found = vocabWithAudio(client.getAssignmentsAtUsersCurrentLevel())
    if found.isEmpty { found = vocabWithAudio(client.getAllAssignments()) }
    subjects = found.shuffled()
  }

  private func buildUI() {
    progressLabel.font = .systemFont(ofSize: 13, weight: .semibold)
    progressLabel.textColor = .secondaryLabel
    progressLabel.textAlignment = .center

    let speaker = UIImage(systemName: "speaker.wave.3.fill",
                          withConfiguration: UIImage.SymbolConfiguration(pointSize: 44))
    playButton.setImage(speaker, for: .normal)
    playButton.tintColor = .white
    playButton.backgroundColor = TKMStyle.radicalColor2
    playButton.layer.cornerRadius = 50
    playButton.clipsToBounds = true
    playButton.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      playButton.widthAnchor.constraint(equalToConstant: 100),
      playButton.heightAnchor.constraint(equalToConstant: 100),
    ])
    if #available(iOS 26.0, *) {
      var config = UIButton.Configuration.prominentGlass()
      config.image = speaker
      config.cornerStyle = .capsule
      config.baseForegroundColor = .white
      playButton.configuration = config
      playButton.backgroundColor = .clear
    }
    playButton.addAction(for: .touchUpInside) { [unowned self] in self.playAudio() }

    wordLabel.font = UIFont(name: TKMStyle.japaneseFontName, size: 44)
    wordLabel.textColor = TKMStyle.Color.label
    wordLabel.textAlignment = .center
    readingLabel.font = UIFont(name: TKMStyle.japaneseFontName, size: 22)
    readingLabel.textColor = .secondaryLabel
    readingLabel.textAlignment = .center
    meaningLabel.font = .systemFont(ofSize: 20, weight: .medium)
    meaningLabel.textColor = TKMStyle.Color.label
    meaningLabel.textAlignment = .center
    meaningLabel.numberOfLines = 0

    answerStack.axis = .vertical
    answerStack.spacing = 8
    answerStack.alignment = .center
    [wordLabel, readingLabel, meaningLabel].forEach { answerStack.addArrangedSubview($0) }
    answerStack.isHidden = true

    actionButton.addAction(for: .touchUpInside) { [unowned self] in self.actionTapped() }

    let stack = UIStackView(arrangedSubviews: [progressLabel, playButton, answerStack])
    stack.axis = .vertical
    stack.alignment = .center
    stack.spacing = 28
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    actionButton.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(actionButton)

    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -30),
      stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
      actionButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      actionButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                                           constant: -24),
    ])
  }

  private func showCurrent(playAudio shouldPlay: Bool) {
    guard !subjects.isEmpty else {
      progressLabel.text = "No vocabulary with audio yet"
      playButton.isHidden = true
      actionButton.isHidden = true
      return
    }
    let subject = subjects[index]
    progressLabel.text = "\(index + 1) / \(subjects.count)"
    wordLabel.text = subject.japanese
    readingLabel.text = subject.readings
      .map { $0.displayText(useKatakanaForOnyomi: Settings.useKatakanaForOnyomi) }
      .joined(separator: ", ")
    meaningLabel.text = subject.commaSeparatedMeanings(showOldMnemonic: Settings.showOldMnemonic)

    revealed = false
    answerStack.isHidden = true
    updateActionButton()
    if shouldPlay { playAudio() }
  }

  private func updateActionButton() {
    actionButton.setTitle(revealed ? "  Next" : "  Reveal", for: .normal)
    actionButton.setImage(UIImage(systemName: revealed ? "arrow.right" : "eye"), for: .normal)
    actionButton.tintColor = TKMStyle.defaultTintColor
    actionButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
  }

  private func playAudio() {
    guard !subjects.isEmpty else { return }
    services.audio.play(subjectID: subjects[index].id, delegate: nil)
  }

  private func actionTapped() {
    if revealed {
      index = (index + 1) % subjects.count
      showCurrent(playAudio: true)
    } else {
      revealed = true
      answerStack.isHidden = false
      updateActionButton()
    }
  }
}
