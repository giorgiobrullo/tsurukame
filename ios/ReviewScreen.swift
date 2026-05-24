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

// SwiftUI rewrite of the review/lesson engine (first pass, behind Settings.useSwiftUIReviews).
// Reuses the proven non-UI pieces: ReviewSession (queue + SRS marking), AnswerChecker, the
// AnswerTextField + TKMKanaInput (wrapped), the audio engine, and the SubjectDetailsView reveal
// (a UITableView subclass, wrapped). The core answer loop is implemented here; the bottom-sheet
// cheats/synonyms, anki mode, success sparkle animations, previous-subject button, custom fonts and
// the wrap-up UI are still TODO and tracked for follow-up.

/// The outcome of answering a review task (consumed by ReviewSession.markAnswer). Previously lived
/// in ReviewViewController.
enum AnswerResult {
  case Correct
  case Incorrect
  case OverrideAnswerCorrect
  case AskAgainLater
  case Exclude

  var correct: Bool {
    self == .Correct || self == .OverrideAnswerCorrect
  }
}

// MARK: - View model

@available(iOS 15.0, *)
final class ReviewViewModel: ObservableObject {
  enum Phase { case answering, markedWrong, revealed }

  let services: TKMServices
  let session: ReviewSession
  let isPracticeSession: Bool
  private let totalItems: Int
  private let haptics = UIImpactFeedbackGenerator(style: .light)

  var onFinished: () -> Void = {}

  @Published var answer = ""
  @Published var phase: Phase = .answering
  /// Bumped whenever the active task changes, so derived views re-read the session.
  @Published private(set) var taskGeneration = 0
  @Published var shakeToggle = false

  init(services: TKMServices, items: [ReviewItem], isPracticeSession: Bool) {
    self.services = services
    self.isPracticeSession = isPracticeSession
    totalItems = items.count
    session = ReviewSession(services: services, items: items, isPracticeSession: isPracticeSession)
    advanceToNext()
  }

  // Derived state for the current task.
  var subject: TKMSubject? { session.activeSubject }
  var taskType: TaskType { session.activeTaskType ?? .meaning }
  var isReading: Bool { taskType == .reading }
  var promptText: String { isReading ? "Reading" : "Meaning" }

  var progress: Double {
    totalItems == 0 ? 0 : min(Double(session.reviewsCompleted) / Double(totalItems), 1)
  }

  var doneCount: Int { session.reviewsCompleted }
  var queueCount: Int { session.activeQueueLength + session.reviewQueueLength }
  var successRateText: String { session.successRateText }

  // MARK: Actions

  func submit() {
    guard phase == .answering, session.activeSubject != nil else { return }

    let normalized = AnswerChecker.normalizedString(answer, taskType: session.activeTaskType,
                                                    alphabet: .hiragana)
    answer = normalized

    let result = AnswerChecker.checkAnswer(normalized,
                                           subject: session.activeSubject,
                                           studyMaterials: session.activeStudyMaterials,
                                           taskType: session.activeTaskType,
                                           localCachingClient: services.localCachingClient)
    switch result {
    case .Precise:
      markCorrect()
    case .Imprecise:
      if Settings.exactMatch { shake() } else { markCorrect() }
    case .Incorrect:
      markWrong()
    case .OtherKanjiReading:
      shake()
    case .MismatchingOkurigana, .ContainsInvalidCharacters:
      shake()
    case .IsReadingButWantMeaning:
      // They know the reading; record it and nudge them to give the meaning.
      session.activeTask.answeredReading = true
      shake()
    }
  }

  /// User overrides a wrong answer ("My answer was correct").
  func overrideCorrect() {
    guard phase == .markedWrong || phase == .revealed else { return }
    _ = session.markAnswer(.OverrideAnswerCorrect, isPracticeSession: isPracticeSession)
    playAudioIfNeeded()
    advanceToNext()
  }

  func reveal() {
    phase = .revealed
  }

  /// Advance from the revealed state to the next task.
  func next() {
    advanceToNext()
  }

  /// Put the current task back in the queue to ask again later.
  func askAgain() {
    session.moveActiveTaskToEnd()
    advanceToNext()
  }

  /// Exclude the current (vocabulary) item from future reviews and drop it from this session.
  func excludeItem() {
    session.setExclude(true)
    session.excludeTask()
    advanceToNext()
  }

  /// Add a meaning synonym, then accept the answer as correct.
  func addSynonym(_ text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty { session.addSynonym(trimmed) }
    _ = session.markAnswer(.OverrideAnswerCorrect, isPracticeSession: isPracticeSession)
    playAudioIfNeeded()
    advanceToNext()
  }

  var canExclude: Bool {
    session.activeSubject?.subjectType == .vocabulary && Settings.allowExcludeItems
  }

  // MARK: Anki mode (reveal then self-mark, no typing)

  var isAnkiMode: Bool {
    guard Settings.ankiMode else { return false }
    switch Settings.ankiModeTaskType {
    case .both: return true
    case .readingOnly: return taskType == .reading
    case .meaningOnly: return taskType == .meaning
    @unknown default: return false
    }
  }

  /// Reveal the answer in Anki mode. Records an attempt as incorrect (overridable via "Correct").
  func ankiShowAnswer() {
    guard phase == .answering else { return }
    _ = session.markAnswer(.Incorrect, isPracticeSession: isPracticeSession)
    phase = .revealed
  }

  func ankiCorrect() { overrideCorrect() }
  func ankiIncorrect() { advanceToNext() } // already marked incorrect; it returns later

  // MARK: Session control

  var canWrapUp: Bool { session.canWrapUp }
  var isWrappingUp: Bool { session.wrappingUp }
  func wrapUp() { session.wrappingUp = true }
  func endSession() { onFinished() }

  func playCurrentAudio() {
    guard let subject = session.activeSubject else { return }
    services.audio.play(subjectID: subject.id, delegate: nil)
  }

  // MARK: Internals

  private func markCorrect() {
    haptics.impactOccurred()
    haptics.prepare()
    _ = session.markAnswer(.Correct, isPracticeSession: isPracticeSession)
    playAudioIfNeeded()
    advanceToNext()
  }

  private func markWrong() {
    _ = session.markAnswer(.Incorrect, isPracticeSession: isPracticeSession)
    if Settings.showAnswerImmediately {
      phase = .revealed
    } else {
      phase = .markedWrong
    }
  }

  private func playAudioIfNeeded() {
    guard Settings.playAudioAutomatically, let subject = session.activeSubject,
          session.activeTaskType == .reading || subject.readings.isEmpty,
          subject.hasVocabulary, !subject.vocabulary.audio.isEmpty else { return }
    services.audio.play(subjectID: subject.id, delegate: nil)
  }

  private func shake() {
    shakeToggle.toggle()
  }

  private func advanceToNext() {
    if session.activeQueueLength == 0, session.reviewQueueLength == 0 {
      onFinished()
      return
    }
    answer = ""
    phase = .answering
    session.nextTask()
    taskGeneration += 1
  }
}

// MARK: - Wrapped UIKit pieces

/// Wraps AnswerTextField + TKMKanaInput so reading answers get romaji→kana conversion exactly like
/// the UIKit review screen.
@available(iOS 15.0, *)
struct AnswerFieldView: UIViewRepresentable {
  @Binding var text: String
  var isReading: Bool
  var isEnabled: Bool
  var onSubmit: () -> Void

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeUIView(context: Context) -> AnswerTextField {
    let field = AnswerTextField()
    field.autocapitalizationType = .none
    field.autocorrectionType = .no
    field.borderStyle = .roundedRect
    field.textAlignment = .center
    field.font = .systemFont(ofSize: 24)
    field.returnKeyType = .next
    field.delegate = context.coordinator.kanaInput
    field.addAction(for: .editingChanged) { [weak field] in
      context.coordinator.parent.text = field?.text ?? ""
    }
    context.coordinator.field = field
    return field
  }

  func updateUIView(_ field: AnswerTextField, context: Context) {
    context.coordinator.parent = self
    if field.text != text { field.text = text }
    field.isEnabled = isEnabled
    field.textColor = isEnabled ? TKMStyle.Color.label : .systemRed
    context.coordinator.kanaInput.enabled = isReading
    context.coordinator.kanaInput.alphabet = .hiragana
    field.useJapaneseKeyboard = isReading && Settings.autoSwitchKeyboard
    field.placeholder = isReading ? "Reading" : "Answer"
    if isEnabled, !field.isFirstResponder {
      DispatchQueue.main.async { field.becomeFirstResponder() }
    }
  }

  final class Coordinator: NSObject, UITextFieldDelegate {
    var parent: AnswerFieldView
    weak var field: AnswerTextField?
    lazy var kanaInput = KanaInput(delegate: self)

    init(_ parent: AnswerFieldView) { self.parent = parent }

    func textFieldShouldReturn(_: UITextField) -> Bool {
      parent.onSubmit()
      return false
    }
  }
}

// MARK: - Screen

@available(iOS 15.0, *)
struct ReviewScreen: View {
  @ObservedObject var model: ReviewViewModel
  let subjectDelegate: SubjectDelegate

  @State private var showMenu = false
  @State private var showSynonymAlert = false
  @State private var synonymText = ""

  var body: some View {
    VStack(spacing: 0) {
      statusBar
      question
      prompt
      if model.phase == .revealed {
        detail
      }
      controls
    }
    .background(Color.tkmBackground.ignoresSafeArea())
    .confirmationDialog("Options", isPresented: $showMenu, titleVisibility: .hidden) {
      if model.phase == .markedWrong || model.phase == .revealed {
        Button("My answer was correct") { model.overrideCorrect() }
      }
      Button("Ask again later") { model.askAgain() }
      if model.taskType == .meaning {
        Button("Add synonym") { synonymText = ""
          showSynonymAlert = true
        }
      }
      if model.canExclude {
        Button("Exclude this item", role: .destructive) { model.excludeItem() }
      }
      if model.canWrapUp, !model.isWrappingUp {
        Button("Wrap up") { model.wrapUp() }
      }
      Button("End session", role: .destructive) { model.endSession() }
      Button("Cancel", role: .cancel) {}
    }
    .alert("Add synonym", isPresented: $showSynonymAlert) {
      TextField("Synonym", text: $synonymText)
      Button("Add") { model.addSynonym(synonymText) }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Accept this meaning as correct from now on.")
    }
  }

  private var statusBar: some View {
    VStack(spacing: 4) {
      ProgressView(value: model.progress)
        .tint(Color(uiColor: TKMStyle.radicalColor2))
      HStack(spacing: 14) {
        Label("\(model.doneCount)", systemImage: "checkmark.circle.fill")
        Label("\(model.queueCount)", systemImage: "tray.full.fill")
        Text(model.successRateText)
        Spacer()
        Button { showMenu = true } label: {
          Image(systemName: "ellipsis.circle")
        }
      }
      .font(.caption.weight(.semibold))
      .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 16)
    .padding(.top, 8)
  }

  @ViewBuilder
  private var question: some View {
    if let subject = model.subject {
      ZStack {
        LinearGradient(colors: TKMStyle.gradient(forSubject: subject).map { Color(cgColor: $0) },
                       startPoint: .top, endPoint: .bottom)
        JapaneseSubjectLabel(subject: subject, size: 64)
          .fixedSize()
          .id(model.taskGeneration)
      }
      .frame(height: 150)
      .modifier(ShakeEffect(animatableData: model.shakeToggle ? 1 : 0))
    }
  }

  private var prompt: some View {
    Text(model.promptText)
      .font(.headline.weight(.bold))
      .foregroundStyle(model.isReading ? .white : Color(uiColor: .label))
      .frame(maxWidth: .infinity)
      .padding(.vertical, 10)
      .background(model.isReading ? Color(uiColor: TKMStyle.Color.grey33)
        : Color(uiColor: TKMStyle.Color.grey80))
  }

  private var detail: some View {
    SubjectDetailContent(services: model.services,
                         subject: model.subject!,
                         studyMaterials: model.session.activeStudyMaterials,
                         assignment: model.session.activeAssignment,
                         task: Settings.showFullAnswer ? nil : model.session.activeTask,
                         delegate: subjectDelegate)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  @ViewBuilder
  private var controls: some View {
    VStack(spacing: 10) {
      if !model.isAnkiMode {
        AnswerFieldView(text: $model.answer,
                        isReading: model.isReading,
                        isEnabled: model.phase == .answering,
                        onSubmit: { model.submit() })
          .frame(height: 44)
          .modifier(ShakeEffect(animatableData: model.shakeToggle ? 1 : 0))
      }

      if model.isAnkiMode {
        if model.phase == .answering {
          button("Show answer", systemImage: "eye") { model.ankiShowAnswer() }
        } else {
          HStack(spacing: 10) {
            button("Incorrect", systemImage: "xmark", tint: .red) { model.ankiIncorrect() }
            button("Correct", systemImage: "checkmark", tint: .green) { model.ankiCorrect() }
          }
        }
      } else {
        switch model.phase {
        case .answering:
          button("Submit", systemImage: "arrow.right") { model.submit() }
        case .markedWrong:
          HStack(spacing: 10) {
            button("I was right", systemImage: "checkmark",
                   tint: .green) { model.overrideCorrect() }
            button("Reveal answer", systemImage: "eye") { model.reveal() }
          }
        case .revealed:
          HStack(spacing: 10) {
            button("I was right", systemImage: "checkmark",
                   tint: .green) { model.overrideCorrect() }
            button("Next", systemImage: "arrow.right") { model.next() }
          }
        }
      }
    }
    .padding(16)
    .animation(.default, value: model.shakeToggle)
  }

  private func button(_ title: String, systemImage: String,
                      tint: Color = Color(uiColor: TKMStyle.radicalColor2),
                      action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Label(title, systemImage: systemImage)
        .font(.headline)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
    .buttonStyle(.borderedProminent)
    .tint(tint)
  }
}

/// A horizontal shake, driven by toggling `animatableData` between 0 and 1.
@available(iOS 15.0, *)
struct ShakeEffect: GeometryEffect {
  var animatableData: CGFloat

  func effectValue(size _: CGSize) -> ProjectionTransform {
    let translation = 8 * sin(animatableData * .pi * 3)
    return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
  }
}

// MARK: - Hosting

@available(iOS 15.0, *)
final class SwiftUIReviewHostingController: UIHostingController<ReviewScreen>, TKMViewController,
  SubjectDelegate {
  private let services: TKMServices
  private let model: ReviewViewModel
  private let isPracticeSession: Bool

  var canSwipeToGoBack: Bool { false }

  init(services: TKMServices, items: [ReviewItem], isPracticeSession: Bool) {
    self.services = services
    self.isPracticeSession = isPracticeSession
    let model = ReviewViewModel(services: services, items: items,
                                isPracticeSession: isPracticeSession)
    self.model = model
    // SubjectDelegate is `self`, which isn't available before super.init; install a placeholder and
    // swap the rootView in immediately after.
    super.init(rootView: ReviewScreen(model: model, subjectDelegate: PlaceholderSubjectDelegate()))
    title = isPracticeSession ? "Self-study" : "Reviews"
    model.onFinished = { [weak self] in self?.finish() }
    rootView = ReviewScreen(model: model, subjectDelegate: self)
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// Entry point for the "wrap-up" applink.
  func wrapUp() { model.wrapUp() }

  /// Real reviews end on the summary screen; practice sessions just pop back.
  private func finish() {
    guard let nav = navigationController else { return }
    if isPracticeSession {
      nav.popViewController(animated: true)
      return
    }
    let summary = ReviewSummaryHostingController(services: services,
                                                 items: model.session.completedReviews)
    // Replace the review screen with the summary so "back" doesn't return into the finished
    // session.
    var vcs = nav.viewControllers
    if let index = vcs.firstIndex(of: self) {
      vcs[index] = summary
    } else {
      vcs.append(summary)
    }
    nav.setViewControllers(vcs, animated: true)
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.isNavigationBarHidden = false
  }

  // MARK: - SubjectDelegate (related-subject taps in the reveal)

  func didTapSubject(_ subject: TKMSubject) {
    navigationController?.pushViewController(SubjectDetailHostingController(services: services,
                                                                            subject: subject),
                                             animated: true)
  }
}

/// No-op SubjectDelegate used only for the brief window before the hosting controller installs
/// itself as the real delegate.
private final class PlaceholderSubjectDelegate: NSObject, SubjectDelegate {
  func didTapSubject(_: TKMSubject) {}
}
