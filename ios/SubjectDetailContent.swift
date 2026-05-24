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

import SwiftUI
import UIKit
import WaniKaniAPI

// Pure-SwiftUI replacement for the old SubjectDetailsView (a UITableView subclass). It reuses the
// existing NSAttributedString rendering helpers (rendered via `Text(AttributedString(...))`) and
// the pixel-precise SubjectChip view (via a self-sizing representable), so the visual output
// matches the original while the container is fully SwiftUI.

private let kFontSize: CGFloat = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
  .pointSize

private let kMeaningSynonymColor = UIColor(red: 0.231, green: 0.6, blue: 0.988, alpha: 1)

private func attrText(_ ns: NSAttributedString) -> Text {
  Text(AttributedString(ns))
}

// MARK: - Attributed-string rendering (moved verbatim from SubjectDetailsView)

private func join(_ arr: [NSAttributedString],
                  with joinString: String) -> NSMutableAttributedString {
  let ret = NSMutableAttributedString()
  for i in 0 ..< arr.count {
    ret.append(arr[i])
    if i != arr.count - 1 { ret.append(attrString(joinString)) }
  }
  return ret
}

private func defaultStringAttrs() -> [NSAttributedString.Key: Any] {
  [.foregroundColor: TKMStyle.Color.label, .backgroundColor: UIColor.clear]
}

private func attrString(_ string: String,
                        attrs: [NSAttributedString.Key: Any]? = nil) -> NSAttributedString {
  NSAttributedString(string: string,
                     attributes: defaultStringAttrs().merging(attrs ?? [:]) { _, new in new })
}

private func renderMeanings(subject: TKMSubject,
                            synonyms: [String]) -> NSAttributedString {
  var strings = [NSAttributedString]()
  for meaning in subject.meanings where meaning.type == .primary {
    strings.append(attrString(meaning.meaning.trimmingCharacters(in: .whitespacesAndNewlines)))
  }
  for synonym in synonyms {
    strings.append(attrString(synonym.trimmingCharacters(in: .whitespacesAndNewlines),
                              attrs: [.foregroundColor: kMeaningSynonymColor]))
  }
  for meaning in subject.meanings {
    if meaning.type != .primary, meaning.type != .blacklist,
       meaning.type != .auxiliaryWhitelist || (subject.hasRadical && Settings.showOldMnemonic) {
      let font = UIFont.systemFont(ofSize: kFontSize, weight: .light)
      strings.append(attrString(meaning.meaning.trimmingCharacters(in: .whitespacesAndNewlines),
                                attrs: [.font: font]))
    }
  }
  return join(strings, with: ", ").string(withFontSize: kFontSize)
}

private func readingTypeLabel(_ reading: TKMReading) -> NSAttributedString? {
  let text: String
  switch reading.type {
  case .onyomi: text = "\u{2009}on"
  case .kunyomi: text = "\u{2009}kun"
  case .nanori: text = "\u{2009}nanori"
  default: return nil
  }
  return NSAttributedString(string: text, attributes: [
    .font: UIFont.systemFont(ofSize: kFontSize * 0.65, weight: .semibold),
    .foregroundColor: TKMStyle.Color.grey33,
  ])
}

private func renderReadings(readings: [TKMReading], primaryOnly: Bool) -> NSAttributedString {
  func render(_ reading: TKMReading, bold: Bool) -> NSAttributedString {
    let font = UIFont.systemFont(ofSize: kFontSize, weight: bold ? .bold : .regular)
    let result = NSMutableAttributedString(attributedString:
      attrString(reading.displayText(useKatakanaForOnyomi: Settings.useKatakanaForOnyomi),
                 attrs: [.font: font as Any]))
    if let label = readingTypeLabel(reading) { result.append(label) }
    return result
  }
  var strings = [NSAttributedString]()
  for reading in readings where reading.isPrimary {
    strings.append(render(reading, bold: !primaryOnly && readings.count > 1))
  }
  if !primaryOnly {
    for reading in readings where !reading.isPrimary {
      strings.append(render(reading, bold: false))
    }
  }
  return join(strings, with: ", ").string(withFontSize: kFontSize)
}

private func renderFormatted(_ text: String, isHint: Bool) -> AttributedString {
  var attributes = defaultStringAttrs()
  if isHint { attributes[.foregroundColor] = TKMStyle.Color.grey33 }
  let ns = render(formattedText: parseFormattedText(text), standardAttributes: attributes)
    .replaceFontSize(kFontSize)
  return AttributedString(ns)
}

// MARK: - Chip flow (pure SwiftUI)

/// A brand-gradient subject chip: the subject's Japanese (white, via JapaneseSubjectLabel so
/// radical
/// glyph images render) on a gradient rounded rect, optionally followed by its meaning.
@available(iOS 16.0, *)
private struct SubjectChipView: View {
  let subject: TKMSubject
  let showMeaning: Bool
  let onTap: () -> Void

  private var gradient: [Color] {
    TKMStyle.gradient(forSubject: subject).map { Color(cgColor: $0) }
  }

  var body: some View {
    Button(action: onTap) {
      HStack(spacing: 8) {
        JapaneseSubjectLabel(subject: subject, size: 18)
          .fixedSize()
          .padding(.horizontal, 6)
          .padding(.vertical, 6)
          .background(LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing))
          .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        if showMeaning {
          Text(subject.primaryMeaning)
            .font(.system(size: kFontSize))
            .foregroundStyle(.primary)
        }
      }
    }
    .buttonStyle(.plain)
  }
}

/// Left-to-right wrapping layout for the chips (replaces the old calculateSubjectChipFrames).
@available(iOS 16.0, *)
private struct ChipFlowLayout: Layout {
  var spacing: CGFloat = 8
  var lineSpacing: CGFloat = 6

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
    let maxWidth = proposal.width ?? .infinity
    var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if x + size.width > maxWidth, x > 0 {
        x = 0
        y += lineHeight + lineSpacing
        lineHeight = 0
      }
      x += size.width + spacing
      lineHeight = max(lineHeight, size.height)
    }
    return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y + lineHeight)
  }

  func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews,
                     cache _: inout ()) {
    var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if x + size.width > bounds.maxX, x > bounds.minX {
        x = bounds.minX
        y += lineHeight + lineSpacing
        lineHeight = 0
      }
      subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
      x += size.width + spacing
      lineHeight = max(lineHeight, size.height)
    }
  }
}

@available(iOS 16.0, *)
private struct ChipFlowRow: View {
  let subjects: [TKMSubject]
  let showMeaning: Bool
  let onTap: (TKMSubject) -> Void

  var body: some View {
    ChipFlowLayout {
      ForEach(subjects, id: \.id) { subject in
        SubjectChipView(subject: subject, showMeaning: showMeaning) { onTap(subject) }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

// MARK: - View model

@available(iOS 15.0, *)
final class SubjectDetailModel: ObservableObject {
  struct Sentence: Identifiable {
    let id = UUID()
    let japanese: AttributedString
    let english: AttributedString
  }

  let services: TKMServices
  let subject: TKMSubject
  let assignment: TKMAssignment?
  let task: ReviewItem?
  weak var delegate: SubjectDelegate?

  // Editing state.
  @Published var synonyms: [String]
  @Published var editingSynonyms = false
  @Published var meaningNote: String
  @Published var readingNote: String
  @Published var showAll = false

  private var studyMaterials: TKMStudyMaterials
  private let hasStudyMaterials: Bool
  private var changed = false

  let meaningShown: Bool
  let readingShown: Bool
  let canReveal: Bool

  init(services: TKMServices, subject: TKMSubject, studyMaterials: TKMStudyMaterials?,
       assignment: TKMAssignment?, task: ReviewItem?, delegate: SubjectDelegate?) {
    self.services = services
    self.subject = subject
    self.assignment = assignment
    self.task = task
    self.delegate = delegate

    hasStudyMaterials = studyMaterials != nil
    if let studyMaterials = studyMaterials {
      self.studyMaterials = studyMaterials
    } else {
      var sm = TKMStudyMaterials()
      sm.subjectID = subject.id
      self.studyMaterials = sm
    }
    synonyms = studyMaterials?.meaningSynonyms ?? []
    meaningNote = studyMaterials.map { services.localCachingClient
      .getMeaningNoteDisplay(studyMaterials: $0)
    } ?? ""
    readingNote = studyMaterials?.readingNote ?? ""

    let isReview = task != nil
    let meaningAttempted = task?.answeredMeaning == true || task?.answer.meaningWrong == true
    let readingAttempted = task?.answeredReading == true || task?.answer.readingWrong == true
    meaningShown = !isReview || meaningAttempted
    readingShown = !isReview || readingAttempted
    // In a review, fields the user hasn't answered yet start hidden behind "Show all information".
    canReveal = isReview && (!meaningShown || !readingShown)
  }

  var meaningText: AttributedString {
    AttributedString(renderMeanings(subject: subject,
                                    synonyms: editingSynonyms ? [] : synonyms))
  }

  func markChanged() { changed = true }

  func subjects(for ids: [Int64]) -> [TKMSubject] {
    ids.compactMap { services.localCachingClient.getSubject(id: $0) }
  }

  func similarKanji() -> [TKMSubject] {
    guard subject.hasKanji else { return [] }
    let currentLevel = services.localCachingClient.getUserInfo()?.level ?? 0
    var seen = Set<Int64>()
    var result = [TKMSubject]()
    func consider(_ s: TKMSubject) {
      guard !seen.contains(s.id),
            Settings.showSimilarKanjiAboveLevel || s.level <= currentLevel else { return }
      seen.insert(s.id)
      result.append(s)
    }
    for id in subject.kanji.visuallySimilarKanjiIds {
      if let s = services.localCachingClient.getSubject(id: id) { consider(s) }
    }
    for similar in subject.kanji.visuallySimilarKanji {
      if let s = services.localCachingClient.getSubject(japanese: String(similar), type: .kanji) {
        consider(s)
      }
    }
    return result
  }

  func usedIn() -> [TKMSubject] {
    subjects(for: subject.amalgamationSubjectIds).sorted { $0.level < $1.level }
  }

  func contextSentences() -> [Sentence] {
    let defaults = defaultStringAttrs()
    func attr(_ s: String) -> NSAttributedString {
      NSAttributedString(string: s, attributes: defaults)
    }
    return subject.vocabulary.sentences.map { sentence in
      let jaNS = highlightOccurrences(of: subject, in: attr(sentence.japanese))
        ?? attr(sentence.japanese)
      let ja = NSMutableAttributedString(attributedString: jaNS).string(withFontSize: kFontSize)
      let en = NSMutableAttributedString(attributedString: attr(sentence.english))
        .string(withFontSize: kFontSize)
      return Sentence(japanese: AttributedString(ja), english: AttributedString(en))
    }
  }

  func statsRows() -> [(String, String)] {
    guard let a = assignment, Settings.showStatsSection else { return [] }
    let df = DateFormatter()
    df.dateStyle = .medium
    df.timeStyle = .short
    var rows = [(String, String)]()
    if a.hasLevel { rows.append(("WaniKani Level", String(a.level))) }
    if a.hasStartedAt {
      if a.hasSrsStageNumber { rows.append(("SRS Stage", a.srsStage.description)) }
      rows.append(("Started", df.string(from: a.startedAtDate)))
      if a.hasAvailableAt { rows.append(("Next Review", df.string(from: a.availableAtDate))) }
      if a.hasPassedAt { rows.append(("Passed", df.string(from: a.passedAtDate))) }
      if a.hasBurnedAt { rows.append(("Burned", df.string(from: a.burnedAtDate))) }
    }
    return rows
  }

  var optionsShown: Bool {
    task == nil && subject.subjectType == .vocabulary && Settings.allowExcludeItems
  }

  var isExcluded: Bool {
    services.localCachingClient.isExcluded(studyMaterials: studyMaterials)
  }

  func setExcluded(_ exclude: Bool) {
    _ = services.localCachingClient.setExcluded(studyMaterials: &studyMaterials,
                                                shouldExclude: exclude)
  }

  func playAudio(delegate: AudioDelegate?) {
    guard subject.hasVocabulary, !subject.vocabulary.audio.isEmpty else { return }
    if services.audio.currentState == .playing {
      services.audio.stopPlayback()
    } else {
      services.audio.play(subjectID: subject.id, delegate: delegate)
    }
  }

  var hasAudio: Bool { subject.hasVocabulary && !subject.vocabulary.audio.isEmpty }

  /// Persists edited synonyms / notes. Mirrors the old saveStudyMaterials().
  func save() {
    guard changed else { return }
    studyMaterials.meaningSynonyms = synonyms
      .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    if hasStudyMaterials || !meaningNote.isEmpty {
      studyMaterials.meaningNote = services.localCachingClient
        .makeMeaningNote(studyMaterials: studyMaterials, note: meaningNote)
    }
    studyMaterials.readingNote = readingNote
    _ = services.localCachingClient.updateStudyMaterial(studyMaterials)
    changed = false
  }
}

// MARK: - Section helpers

@available(iOS 15.0, *)
private struct DetailSection<Content: View>: View {
  let title: String?
  @ViewBuilder let content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let title = title {
        Text(title.uppercased())
          .font(.footnote.weight(.semibold))
          .foregroundStyle(.secondary)
      }
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 16)
    .padding(.vertical, 6)
  }
}

// MARK: - Main view

@available(iOS 15.0, *)
struct SubjectDetailContent: View {
  @StateObject private var model: SubjectDetailModel

  init(services: TKMServices, subject: TKMSubject, studyMaterials: TKMStudyMaterials?,
       assignment: TKMAssignment?, task: ReviewItem?, delegate: SubjectDelegate) {
    _model = StateObject(wrappedValue: SubjectDetailModel(services: services, subject: subject,
                                                          studyMaterials: studyMaterials,
                                                          assignment: assignment, task: task,
                                                          delegate: delegate))
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 4) {
        if model.subject.hasRadical { radicalSections }
        if model.subject.hasKanji { kanjiSections }
        if model.subject.hasVocabulary { vocabularySections }

        if model.canReveal, !model.showAll {
          showAllButton
        }

        if model.subject.hasVocabulary, contextSentencesVisible {
          contextSentencesSection
          partsOfSpeechSection
        }

        statsSection
        artworkSection
        optionsSection
        devOptionsSection
      }
      .padding(.vertical, 8)
    }
    .background(Color(uiColor: TKMStyle.Color.background))
    .onDisappear { model.save() }
  }

  // Whether the answer-hidden sections are currently visible.
  private var revealed: Bool { !model.canReveal || model.showAll }
  private var meaningVisible: Bool { model.meaningShown || revealed }
  private var readingVisible: Bool { model.readingShown || revealed }
  private var contextSentencesVisible: Bool { model.meaningShown || revealed }

  // MARK: Radical

  @ViewBuilder private var radicalSections: some View {
    if meaningVisible { meaningSection }
    if meaningVisible {
      explanationSection(title: "Mnemonic", text: model.subject.radical.mnemonic,
                         note: .meaning)
      if Settings.showOldMnemonic, !model.subject.radical.deprecatedMnemonic.isEmpty {
        explanationSection(title: "Old Mnemonic", text: model.subject.radical.deprecatedMnemonic,
                           note: nil)
      }
    }
    chipListSection(title: "Used in", subjects: model.usedIn())
  }

  // MARK: Kanji

  @ViewBuilder private var kanjiSections: some View {
    if meaningVisible { meaningSection }
    if readingVisible { readingSection }
    chipCollectionSection(title: "Radicals", ids: model.subject.componentSubjectIds)
    if meaningVisible {
      explanationSection(title: "Meaning Explanation", text: model.subject.kanji.meaningMnemonic,
                         hint: model.subject.kanji.meaningHint, note: .meaning)
    }
    if readingVisible {
      explanationSection(title: "Reading Explanation", text: model.subject.kanji.readingMnemonic,
                         hint: model.subject.kanji.readingHint, note: .reading)
    }
    chipListSection(title: "Visually Similar Kanji", subjects: model.similarKanji())
    chipListSection(title: "Used in", subjects: model.usedIn())
  }

  // MARK: Vocabulary

  @ViewBuilder private var vocabularySections: some View {
    if meaningVisible { meaningSection }
    if readingVisible { readingSection }
    chipCollectionSection(title: "Kanji", ids: model.subject.componentSubjectIds)
    if meaningVisible {
      explanationSection(title: "Meaning Explanation",
                         text: model.subject.vocabulary.meaningExplanation, note: .meaning)
    }
    if readingVisible {
      explanationSection(title: "Reading Explanation",
                         text: model.subject.vocabulary.readingExplanation, note: .reading)
    }
  }

  // MARK: Meaning (+ synonym editing)

  private var meaningSection: some View {
    DetailSection(title: "Meaning") {
      HStack(alignment: .top) {
        attrText(NSAttributedString(model.meaningText))
          .frame(maxWidth: .infinity, alignment: .leading)
        Button {
          withAnimation { model.editingSynonyms.toggle() }
        } label: {
          Image(systemName: model.editingSynonyms ? "checkmark" : "pencil")
        }
        .buttonStyle(.borderless)
      }
      if model.editingSynonyms {
        ForEach(model.synonyms.indices, id: \.self) { i in
          HStack {
            TextField("Synonym", text: Binding(
              get: { i < model.synonyms.count ? model.synonyms[i] : "" },
              set: { if i < model.synonyms.count { model.synonyms[i] = $0
                model.markChanged()
              } }
            ))
            .textFieldStyle(.roundedBorder)
            Button(role: .destructive) {
              if i < model.synonyms.count { model.synonyms.remove(at: i)
                model.markChanged()
              }
            } label: { Image(systemName: "xmark.circle.fill") }
              .buttonStyle(.borderless)
          }
        }
        Button {
          model.synonyms.append("")
          model.markChanged()
        } label: {
          Label("Add synonym", systemImage: "plus.circle")
        }
        .buttonStyle(.borderless)
      }
    }
  }

  // MARK: Reading (+ audio)

  private var readingSection: some View {
    var readings = model.subject.readings
    if readings.isEmpty {
      var r = TKMReading()
      r.isPrimary = true
      r.reading = model.subject.japanese
      readings = [r]
    }
    let primaryOnly = model.subject.hasKanji && !Settings.showAllReadings
    let rendered = renderReadings(readings: readings, primaryOnly: primaryOnly)
    return DetailSection(title: "Reading") {
      HStack(alignment: .firstTextBaseline) {
        attrText(rendered).frame(maxWidth: .infinity, alignment: .leading)
        if model.hasAudio { AudioButton(model: model) }
      }
    }
  }

  // MARK: Explanations / mnemonics (+ notes)

  private enum NoteKind { case meaning, reading }

  @ViewBuilder
  private func explanationSection(title: String, text: String, hint: String? = nil,
                                  note: NoteKind?) -> some View {
    if !text.isEmpty {
      DetailSection(title: title) {
        attrText(NSAttributedString(renderFormatted(text, isHint: false)))
          .frame(maxWidth: .infinity, alignment: .leading)
        if let hint = hint, !hint.isEmpty {
          attrText(NSAttributedString(renderFormatted(hint, isHint: true)))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        if let note = note { noteEditor(note) }
      }
    }
  }

  @ViewBuilder
  private func noteEditor(_ kind: NoteKind) -> some View {
    let binding = Binding<String>(get: { kind == .meaning ? model.meaningNote : model.readingNote },
                                  set: {
                                    if kind == .meaning { model.meaningNote = $0 }
                                    else { model.readingNote = $0 }
                                    model.markChanged()
                                  })
    HStack(alignment: .top) {
      Image(systemName: "note.text").foregroundStyle(.secondary)
      TextField("Add a note", text: binding)
        .textFieldStyle(.plain)
    }
    .font(.system(size: kFontSize))
    .padding(.top, 4)
  }

  // MARK: Chips

  @ViewBuilder
  private func chipCollectionSection(title: String, ids: [Int64]) -> some View {
    let subjects = model.subjects(for: ids)
    if !subjects.isEmpty {
      DetailSection(title: title) {
        ChipFlowRow(subjects: subjects, showMeaning: false) { model.delegate?.didTapSubject($0) }
      }
    }
  }

  @ViewBuilder
  private func chipListSection(title: String, subjects: [TKMSubject]) -> some View {
    if !subjects.isEmpty {
      DetailSection(title: title) {
        ChipFlowRow(subjects: subjects, showMeaning: true) { model.delegate?.didTapSubject($0) }
      }
    }
  }

  // MARK: Context sentences

  private var contextSentencesSection: some View {
    let sentences = model.contextSentences()
    return Group {
      if !sentences.isEmpty {
        DetailSection(title: "Context Sentences") {
          ForEach(sentences) { sentence in
            VStack(alignment: .leading, spacing: 2) {
              attrText(NSAttributedString(sentence.japanese))
              attrText(NSAttributedString(sentence.english))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 6)
          }
        }
      }
    }
  }

  private var partsOfSpeechSection: some View {
    let text = model.subject.vocabulary.commaSeparatedPartsOfSpeech
    return Group {
      if !text.isEmpty {
        DetailSection(title: "Part of Speech") {
          Text(text).font(.system(size: kFontSize))
        }
      }
    }
  }

  // MARK: Stats / artwork / options / dev

  private var statsSection: some View {
    let rows = model.statsRows()
    return Group {
      if !rows.isEmpty {
        DetailSection(title: "Stats") {
          ForEach(rows, id: \.0) { row in
            HStack {
              Text(row.0)
              Spacer()
              Text(row.1).foregroundStyle(.secondary)
            }
            .font(.system(size: kFontSize))
          }
        }
      }
    }
  }

  @ViewBuilder private var artworkSection: some View {
    if Settings.showArtwork, model.services.reachability.isReachable(),
       ArtworkManager.contains(subjectID: model.subject.id),
       let urlString = ArtworkManager.artworkFullURL(subjectID: model.subject.id),
       let url = URL(string: urlString) {
      DetailSection(title: "Artwork by @AmandaBear") {
        AsyncImage(url: url) { phase in
          switch phase {
          case let .success(image): image.resizable().scaledToFit()
          case .failure: Text("Error loading image")
          default: ProgressView()
          }
        }
        .frame(maxWidth: .infinity)
      }
    }
  }

  @ViewBuilder private var optionsSection: some View {
    if model.optionsShown {
      DetailSection(title: "Options") {
        Toggle(isOn: Binding(get: { model.isExcluded }, set: { model.setExcluded($0) })) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Exclude this item")
            Text("Excluded items do not appear in lessons or reviews.")
              .font(.caption).foregroundStyle(.secondary)
          }
        }
      }
    }
  }

  @ViewBuilder private var devOptionsSection: some View {
    if FeatureFlags.showSubjectDeveloperOptions {
      DetailSection(title: "Developer options") {
        Button("Open practice review") { model.delegate?.openPracticeReview(model.subject) }
      }
    }
  }

  private var showAllButton: some View {
    Button {
      withAnimation { model.showAll = true }
    } label: {
      Text("Show all information")
        .fontWeight(.semibold)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color(uiColor: TKMStyle.Color.grey80)))
    }
    .buttonStyle(.plain)
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
  }
}

// Small audio button that reflects the Audio service playback state.
@available(iOS 15.0, *)
private struct AudioButton: View {
  let model: SubjectDetailModel
  @StateObject private var observer = AudioObserver()

  var body: some View {
    Button {
      model.playAudio(delegate: observer)
    } label: {
      Image(systemName: observer.playing ? "stop.fill" : "speaker.wave.2.fill")
    }
    .buttonStyle(.borderless)
    .disabled(observer.loading)
  }
}

@available(iOS 15.0, *)
private final class AudioObserver: NSObject, ObservableObject, AudioDelegate {
  @Published var playing = false
  @Published var loading = false

  func audioPlaybackStateChanged(state: Audio.PlaybackState) {
    switch state {
    case .loading: loading = true
      playing = false
    case .playing: loading = false
      playing = true
    case .finished: loading = false
      playing = false
    }
  }
}
