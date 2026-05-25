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
  /// Set when an answer is marked correct, to drive the one-shot success animation.
  @Published var successEvent: SuccessEvent?
  /// The most recently completed subject, shown as a tappable chip in the bottom-left corner.
  @Published var previousSubject: TKMSubject?
  /// Bumped when `previousSubject` changes, so the chip replays its fly-to-corner animation.
  @Published var flyToken = UUID()

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
  /// Radicals are quizzed on their *name*, everything else on its *meaning*.
  var promptText: String {
    if isReading { return "Reading" }
    return subject?.subjectType == .radical ? "Name" : "Meaning"
  }

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
    let marked = session.markAnswer(.OverrideAnswerCorrect, isPracticeSession: isPracticeSession)
    finishCorrect(marked)
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
    let marked = session.markAnswer(.OverrideAnswerCorrect, isPracticeSession: isPracticeSession)
    finishCorrect(marked)
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
    let marked = session.markAnswer(.Correct, isPracticeSession: isPracticeSession)
    finishCorrect(marked)
  }

  /// Shared tail for every "correct" path: play audio, fire the success animation, advance.
  private func finishCorrect(_ marked: ReviewSession.MarkResult) {
    playAudioIfNeeded()
    emitSuccess(marked)
    advanceToNext()
  }

  /// Build the one-shot success event from the marked result, honouring the animation settings.
  private func emitSuccess(_ marked: ReviewSession.MarkResult) {
    // Capture the just-finished subject (still active until advanceToNext) for the corner chip.
    if marked.subjectFinished, let finished = session.activeSubject {
      previousSubject = finished
      flyToken = UUID()
    }
    var billboard: SuccessEvent.Billboard?
    if marked.didLevelUp, Settings.animateLevelUpPopup {
      // Only the first stage of each SRS category gets the celebratory popup.
      switch marked.newSrsStage {
      case .guru1, .master, .enlightened, .burned:
        let category = marked.newSrsStage.category
        billboard = .init(text: category.description,
                          color: Color(uiColor: TKMStyle.color(forSRSStageCategory: category)))
      default: break
      }
    }
    successEvent = SuccessEvent(showParticles: Settings.animateParticleExplosion,
                                showPlusOne: marked.subjectFinished && Settings.animatePlusOne,
                                billboard: billboard)
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

  @State private var showSynonymAlert = false
  @State private var synonymText = ""
  /// Frames in `reviewSpace`, used to anchor the success animation and the corner chip.
  @State private var answerFrame: CGRect = .zero
  @State private var heroFrame: CGRect = .zero

  private static let reviewSpace = "reviewSpace"
  private var brand: Color { Color(uiColor: TKMStyle.radicalColor2) }
  private var isRevealed: Bool { model.phase == .revealed }

  var body: some View {
    VStack(spacing: 0) {
      hero
      prompt
      if isRevealed { detail }
      controls
    }
    .background(Color.tkmBackground.ignoresSafeArea())
    .coordinateSpace(name: Self.reviewSpace)
    .overlay(successOverlay)
    .overlay(previousSubjectOverlay)
    .onPreferenceChange(AnswerFrameKey.self) { answerFrame = $0 }
    .onPreferenceChange(HeroFrameKey.self) { heroFrame = $0 }
    .alert("Add synonym", isPresented: $showSynonymAlert) {
      TextField("Synonym", text: $synonymText)
      Button("Add") { model.addSynonym(synonymText) }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Accept this meaning as correct from now on.")
    }
  }

  // MARK: Hero (gradient + character + stats), fills the screen while answering.

  @ViewBuilder
  private var hero: some View {
    if let subject = model.subject {
      ZStack(alignment: .top) {
        LinearGradient(colors: TKMStyle.gradient(forSubject: subject).map { Color(cgColor: $0) },
                       startPoint: .top, endPoint: .bottom)
        JapaneseSubjectLabel(subject: subject, size: isRevealed ? 40 : 80)
          .fixedSize()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .id(model.taskGeneration)
        statsOverlay
      }
      .frame(maxWidth: .infinity, maxHeight: isRevealed ? 128 : .infinity)
      .clipped()
      .background(GeometryReader { geo in
        Color.clear.preference(key: HeroFrameKey.self,
                               value: geo.frame(in: .named(Self.reviewSpace)))
      })
      .modifier(ShakeEffect(animatableData: model.shakeToggle ? 1 : 0))
    }
  }

  /// Slim, white-on-gradient progress + counts overlaid at the top of the hero.
  private var statsOverlay: some View {
    VStack(spacing: 6) {
      ProgressView(value: model.progress)
        .tint(.white)
      HStack(spacing: 16) {
        Label("\(model.doneCount)", systemImage: "checkmark.circle.fill")
        Label("\(model.queueCount)", systemImage: "tray.full.fill")
        Text(model.successRateText)
        Spacer()
      }
      .font(.footnote.weight(.semibold))
      .foregroundStyle(.white)
    }
    .padding(.horizontal, 16)
    .padding(.top, 8)
    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
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

  // MARK: Bottom controls

  @ViewBuilder
  private var controls: some View {
    VStack(spacing: 10) {
      if model.isAnkiMode {
        ankiControls
      } else {
        switch model.phase {
        case .answering, .markedWrong:
          HStack(spacing: 10) {
            optionsMenu
            AnswerFieldView(text: $model.answer,
                            isReading: model.isReading,
                            isEnabled: model.phase == .answering,
                            onSubmit: { model.submit() })
              .frame(height: 52)
              .background(answerFrameReader)
              .modifier(ShakeEffect(animatableData: model.shakeToggle ? 1 : 0))
            arrowButton(model.phase == .answering ? "arrow.right" : "eye") {
              if model.phase == .answering { model.submit() } else { model.reveal() }
            }
          }
        case .revealed:
          HStack(spacing: 10) {
            optionsMenu
            wideButton("I was right", systemImage: "checkmark", filled: false,
                       tint: .green) { model.overrideCorrect() }
            wideButton("Next", systemImage: "arrow.right", filled: true) { model.next() }
          }
        }
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .animation(.default, value: model.shakeToggle)
  }

  @ViewBuilder
  private var ankiControls: some View {
    if model.phase == .answering {
      HStack(spacing: 10) {
        optionsMenu
        wideButton("Show answer", systemImage: "eye", filled: true) { model.ankiShowAnswer() }
      }
    } else {
      HStack(spacing: 10) {
        optionsMenu
        wideButton("Incorrect", systemImage: "xmark", filled: true,
                   tint: .red) { model.ankiIncorrect() }
        wideButton("Correct", systemImage: "checkmark", filled: true,
                   tint: .green) { model.ankiCorrect() }
      }
    }
  }

  /// Anchored pull-down menu of per-review actions (replaces the old slide-out drawer). Lives at
  /// the bottom-left so it's reachable one-handed and opens attached to its button.
  private var optionsMenu: some View {
    Menu {
      if model.phase == .markedWrong || model.phase == .revealed {
        Button("My answer was correct", systemImage: "checkmark") { model.overrideCorrect() }
      }
      Button("Ask again later", systemImage: "arrow.uturn.left") { model.askAgain() }
      if model.taskType == .meaning {
        Button("Add synonym", systemImage: "plus") { synonymText = ""
          showSynonymAlert = true
        }
      }
      if model.canExclude {
        Button("Exclude this item", systemImage: "nosign", role: .destructive) {
          model.excludeItem()
        }
      }
      if model.canWrapUp, !model.isWrappingUp {
        Button("Wrap up", systemImage: "flag.checkered") { model.wrapUp() }
      }
      Button("End session", systemImage: "xmark", role: .destructive) { model.endSession() }
    } label: {
      Image(systemName: "ellipsis")
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(.secondary)
        .frame(width: 52, height: 52)
        .background(Color(uiColor: TKMStyle.Color.cellBackground),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
  }

  /// Compact square action button that sits to the right of the answer field.
  private func arrowButton(_ systemImage: String,
                           action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: 20, weight: .bold))
        .foregroundStyle(.white)
        .frame(width: 52, height: 52)
        .background(brand, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private func wideButton(_ title: String, systemImage: String, filled: Bool,
                          tint: Color? = nil, action: @escaping () -> Void) -> some View {
    let label = Label(title, systemImage: systemImage)
      .font(.headline)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 10)
    if filled {
      Button(action: action) { label }.buttonStyle(.borderedProminent).tint(tint ?? brand)
    } else {
      Button(action: action) { label }.buttonStyle(.bordered).tint(tint ?? brand)
    }
  }

  // MARK: Success animation plumbing

  private var answerFrameReader: some View {
    GeometryReader { geo in
      Color.clear.preference(key: AnswerFrameKey.self,
                             value: geo.frame(in: .named(Self.reviewSpace)))
    }
  }

  @ViewBuilder
  private var successOverlay: some View {
    GeometryReader { geo in
      if let event = model.successEvent {
        let anchor = answerFrame == .zero
          ? CGRect(x: geo.size.width / 2 - 80, y: geo.size.height * 0.78, width: 160, height: 52)
          : answerFrame
        SuccessBurst(event: event, anchor: anchor) { model.successEvent = nil }
          .id(event.id)
      }
    }
    .allowsHitTesting(false)
  }

  /// The just-finished subject, flying from the hero into a tappable chip in the bottom-left.
  @ViewBuilder
  private var previousSubjectOverlay: some View {
    if let prev = model.previousSubject, heroFrame != .zero, !isRevealed {
      let size: CGFloat = 56
      let from = CGPoint(x: heroFrame.midX, y: heroFrame.midY)
      let to = CGPoint(x: heroFrame.minX + 16 + size / 2, y: heroFrame.maxY - 16 - size / 2)
      PreviousSubjectChip(subject: prev,
                          colors: TKMStyle.gradient(forSubject: prev).map { Color(cgColor: $0) },
                          size: size, from: from, to: to) { subjectDelegate.didTapSubject(prev) }
        .id(model.flyToken)
    }
  }
}

private struct AnswerFrameKey: PreferenceKey {
  static var defaultValue: CGRect = .zero
  static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

private struct HeroFrameKey: PreferenceKey {
  static var defaultValue: CGRect = .zero
  static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

/// A subject chip that animates from `from` (hero centre, large) to `to` (bottom-left corner,
/// small) on appear, then rests there as a tappable shortcut to the just-finished subject.
@available(iOS 15.0, *)
struct PreviousSubjectChip: View {
  let subject: TKMSubject
  let colors: [Color]
  let size: CGFloat
  let from: CGPoint
  let to: CGPoint
  var onTap: () -> Void

  @State private var landed = false

  var body: some View {
    Button(action: onTap) {
      ZStack {
        LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
        JapaneseSubjectLabel(subject: subject, size: landed ? 24 : 52)
          .fixedSize()
      }
      .frame(width: landed ? size : size * 1.9, height: landed ? size : size * 1.9)
      .clipShape(RoundedRectangle(cornerRadius: landed ? 12 : 18, style: .continuous))
      .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
    }
    .buttonStyle(.plain)
    .position(landed ? to : from)
    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: landed)
    .onAppear { DispatchQueue.main.async { landed = true } }
  }
}

// MARK: - Success animation

/// A one-shot success celebration, mirroring the original UIKit `SuccessAnimation`: a particle
/// explosion from the answer field, an optional "+1", and an optional SRS level-up billboard.
@available(iOS 15.0, *)
struct SuccessEvent: Equatable {
  struct Billboard: Equatable {
    let text: String
    let color: Color
  }

  let id = UUID()
  var showParticles: Bool
  var showPlusOne: Bool
  var billboard: Billboard?

  static func == (lhs: SuccessEvent, rhs: SuccessEvent) -> Bool { lhs.id == rhs.id }
}

@available(iOS 15.0, *)
struct SuccessBurst: View {
  let event: SuccessEvent
  let anchor: CGRect
  var onDone: () -> Void

  @State private var exploded = false
  @State private var billboardLeaving = false

  private let sparks: [Spark]
  private var origin: CGPoint { CGPoint(x: anchor.midX, y: anchor.minY) }

  init(event: SuccessEvent, anchor: CGRect, onDone: @escaping () -> Void) {
    self.event = event
    self.anchor = anchor
    self.onDone = onDone
    sparks = event.showParticles ? Spark.burst(width: anchor.width) : []
  }

  private var maxDuration: Double {
    if event.billboard != nil { return 2.6 }
    if event.showPlusOne { return 1.4 }
    return 0.9
  }

  var body: some View {
    ZStack {
      ForEach(sparks) { spark in
        Circle()
          .fill(spark.color)
          .frame(width: spark.size, height: spark.size)
          .scaleEffect(exploded ? 0.01 : 1)
          .opacity(exploded ? 0 : 1)
          .position(x: origin.x + spark.startDX + (exploded ? spark.dx : 0),
                    y: origin.y + (exploded ? spark.dy : 0))
          .animation(.easeOut(duration: spark.duration), value: exploded)
      }

      if event.showPlusOne {
        Text("+1")
          .font(.system(size: 24, weight: .heavy))
          .foregroundStyle(.white)
          .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
          .scaleEffect(exploded ? 1.0 : 0.6)
          .opacity(exploded ? 0 : 1)
          .position(x: origin.x, y: origin.y - (exploded ? 130 : 12))
          .animation(.easeOut(duration: 1.1), value: exploded)
      }

      if let billboard = event.billboard {
        Text(billboard.text)
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 14)
          .padding(.vertical, 7)
          .background(billboard.color, in: Capsule())
          .overlay(Capsule().strokeBorder(.white.opacity(0.6), lineWidth: 1.5))
          .shadow(color: .black.opacity(0.4), radius: 4)
          .scaleEffect(exploded ? 1 : 0.2)
          .opacity(billboardLeaving ? 0 : (exploded ? 1 : 0))
          .position(x: origin.x, y: origin.y - (exploded ? 150 : 20))
          .animation(.spring(response: 0.5, dampingFraction: 0.6), value: exploded)
          .animation(.easeIn(duration: 0.5), value: billboardLeaving)
      }
    }
    .onAppear {
      // Flip outside withAnimation so each spark animates with its own duration.
      DispatchQueue.main.async { exploded = true }
      if event.billboard != nil {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) { billboardLeaving = true }
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + maxDuration) { onDone() }
    }
  }
}

@available(iOS 15.0, *)
private struct Spark: Identifiable {
  let id = UUID()
  let dx: CGFloat
  let dy: CGFloat
  let startDX: CGFloat
  let size: CGFloat
  let color: Color
  let duration: Double

  /// 40 sparks fanning upward and out, skewed by a random offset (as in the original).
  static func burst(width: CGFloat) -> [Spark] {
    let colors = [Color(uiColor: TKMStyle.explosionColor1),
                  Color(uiColor: TKMStyle.explosionColor2)]
    return (0 ..< 40).map { _ in
      let offset = CGFloat.random(in: -1 ... 1)
      let angle = -(.pi * 0.3) * offset
      let distance = CGFloat.random(in: 60 ... 150)
      return Spark(dx: -distance * sin(angle),
                   dy: -distance * cos(angle),
                   startDX: 0.25 * offset * width,
                   size: CGFloat.random(in: 8 ... 11),
                   color: colors.randomElement()!,
                   duration: Double.random(in: 0.5 ... 0.7))
    }
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
