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

// Reusable SwiftUI subject browser: the radicals / kanji / vocabulary list shared by the
// by-level and by-SRS-category screens. Each row is a brand-gradient chip (the same look as the old
// SubjectModelItem cell); tapping pushes the existing UIKit subject-detail screen.

enum SubjectListSource: Hashable {
  case level(Int)
  case category(SRSStageCategory)
}

@available(iOS 15.0, *)
struct SubjectRowData: Identifiable {
  let id: Int64
  let subject: TKMSubject
  let assignment: TKMAssignment?
}

@available(iOS 15.0, *)
struct SubjectListSection: Identifiable {
  let id = UUID()
  let title: String
  let rows: [SubjectRowData]
}

/// Builds the grouped, sorted sections from a source, mirroring `SubjectsByLevelViewController`.
@available(iOS 15.0, *)
enum SubjectListBuilder {
  static func sections(services: TKMServices, source: SubjectListSource) -> [SubjectListSection] {
    guard let lcc = services.localCachingClient else { return [] }
    let assignments: [TKMAssignment]
    switch source {
    case let .level(level): assignments = lcc.getAssignments(level: level)
    case let .category(category): assignments = lcc.getAssignmentsInCategory(category: category)
    }

    var radicals = [SubjectRowData](), kanji = [SubjectRowData](), vocab = [SubjectRowData]()
    for assignment in assignments {
      guard let subject = lcc.getSubject(id: assignment.subjectID) else { continue }
      let row = SubjectRowData(id: assignment.subjectID, subject: subject, assignment: assignment)
      switch subject.subjectType {
      case .radical: radicals.append(row)
      case .kanji: kanji.append(row)
      case .vocabulary: vocab.append(row)
      default: break
      }
    }

    radicals.sort(by: order)
    kanji.sort(by: order)
    vocab.sort(by: order)

    var sections = [SubjectListSection]()
    if !radicals.isEmpty { sections.append(.init(title: "Radicals (\(radicals.count))",
                                                 rows: radicals)) }
    if !kanji.isEmpty { sections.append(.init(title: "Kanji (\(kanji.count))", rows: kanji)) }
    if !vocab.isEmpty { sections.append(.init(title: "Vocabulary (\(vocab.count))", rows: vocab)) }
    return sections
  }

  /// Locked last, then review-stage, then lesson-stage, then by ascending SRS stage.
  private static func order(_ a: SubjectRowData, _ b: SubjectRowData) -> Bool {
    guard let x = a.assignment, let y = b.assignment else { return false }
    if x.isLocked != y.isLocked { return !x.isLocked }
    if x.isReviewStage != y.isReviewStage { return x.isReviewStage }
    if x.isLessonStage != y.isLessonStage { return x.isLessonStage }
    return x.srsStage < y.srsStage
  }
}

// MARK: - Views

/// Renders a subject's Japanese using the existing `japaneseText()` (so image-only radicals show
/// their glyph image), wrapped in a UILabel for pixel-faithful output.
@available(iOS 15.0, *)
struct JapaneseSubjectLabel: UIViewRepresentable {
  let subject: TKMSubject
  var size: CGFloat = 24

  func makeUIView(context _: Context) -> UILabel {
    let label = UILabel()
    label.textColor = .white
    label.tintColor = .white
    label.setContentHuggingPriority(.required, for: .horizontal)
    label.setContentCompressionResistancePriority(.required, for: .horizontal)
    return label
  }

  func updateUIView(_ label: UILabel, context _: Context) {
    label.font = UIFont(name: TKMStyle.japaneseFontName, size: size)
    label.attributedText = japaneseText(subject, imageSize: size)
  }
}

@available(iOS 15.0, *)
struct SubjectRow: View {
  let data: SubjectRowData
  let onTap: (TKMSubject) -> Void

  private var gradient: [Color] {
    TKMStyle.gradient(forSubject: data.subject).map { Color(cgColor: $0) }
  }

  private var reading: String? {
    switch data.subject.subjectType {
    case .kanji: return data.subject.commaSeparatedPrimaryReadings
    case .vocabulary:
      return data.subject.readings.isEmpty ? nil : data.subject.commaSeparatedReadings
    default: return nil
    }
  }

  private var meaning: String {
    data.subject.commaSeparatedMeanings(showOldMnemonic: Settings.showOldMnemonic)
  }

  var body: some View {
    Button { onTap(data.subject) } label: {
      HStack(spacing: 12) {
        Text("\(data.subject.level)")
          .font(.caption.weight(.bold))
          .foregroundStyle(.white.opacity(0.85))
          .frame(minWidth: 22)
        JapaneseSubjectLabel(subject: data.subject)
          .fixedSize()
        Spacer(minLength: 12)
        VStack(alignment: .trailing, spacing: 1) {
          if let reading = reading {
            Text(reading).font(.subheadline)
          }
          Text(meaning).font(.subheadline)
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.trailing)
        .lineLimit(2)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      .background(LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing))
    }
    .buttonStyle(.plain)
    .listRowInsets(EdgeInsets())
    .listRowSeparator(.hidden)
  }
}

@available(iOS 15.0, *)
struct SubjectListScreen: View {
  let sections: [SubjectListSection]
  let onTap: (TKMSubject) -> Void

  var body: some View {
    List {
      ForEach(sections) { section in
        Section(section.title) {
          ForEach(section.rows) { row in
            SubjectRow(data: row, onTap: onTap)
          }
        }
      }
    }
    .listStyle(.plain)
  }
}

/// Hosts a `SubjectListScreen` and pushes the existing UIKit subject-detail screen on tap.
@available(iOS 15.0, *)
final class SubjectListHostingController: UIHostingController<SubjectListScreen>,
  TKMViewController {
  private let services: TKMServices

  var canSwipeToGoBack: Bool { true }

  init(services: TKMServices, title: String, source: SubjectListSource) {
    self.services = services
    let sections = SubjectListBuilder.sections(services: services, source: source)
    super.init(rootView: SubjectListScreen(sections: sections, onTap: { _ in }))
    self.title = title
    rootView = SubjectListScreen(sections: sections, onTap: { [weak self] subject in
      self?.openDetails(subject)
    })
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.isNavigationBarHidden = false
  }

  private func openDetails(_ subject: TKMSubject) {
    navigationController?.pushViewController(SubjectDetailHostingController(services: services,
                                                                            subject: subject),
                                             animated: true)
  }
}
