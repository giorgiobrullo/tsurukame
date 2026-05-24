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
import WaniKaniAPI

// The review and lessons flows as nested SwiftUI NavigationStacks, replacing the contained
// UINavigationController + hosting controllers. The answer/typing loop (ReviewScreen) and the
// teaching pages (LessonsScreen) are unchanged; this only owns the flow navigation:
// review -> summary, lessons -> quiz -> summary, and subject-detail pushes from any of them.

/// Builds the end-of-session summary inputs from the completed items (moved from
/// ReviewSummaryHostingController) and renders the existing ReviewSummaryScreen with a Done button.
@available(iOS 16.0, *)
struct ReviewSummaryView: View {
  let services: TKMServices
  let items: [ReviewItem]
  let onTapSubject: (TKMSubject) -> Void
  let onReReview: () -> Void
  let onDone: () -> Void

  var body: some View {
    let summary = build()
    return ReviewSummaryScreen(correct: summary.correct, total: items.count,
                               incorrectCount: summary.incorrect, groups: summary.groups,
                               onReReview: onReReview, onTapSubject: onTapSubject)
      .navigationTitle("Reviews")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) { Button("Done", action: onDone) }
      }
  }

  private func build()
    -> (correct: Int, incorrect: Int, groups: [ReviewSummaryScreen.LevelGroup]) {
    let currentLevel = services.localCachingClient.getUserInfo()?.level ?? 0
    var incorrectByLevel = [Int32: [ReviewItem]]()
    var correct = 0
    for item in items {
      if !item.answer.meaningWrong, !item.answer.readingWrong {
        correct += 1
      } else {
        incorrectByLevel[item.assignment.level, default: []].append(item)
      }
    }
    let incorrect = incorrectByLevel.values.reduce(0) { $0 + $1.count }
    var groups = [ReviewSummaryScreen.LevelGroup]()
    for level in incorrectByLevel.keys.sorted(by: >) {
      let rows = incorrectByLevel[level]!.compactMap { item -> SubjectRowData? in
        let subject = item.subject
          ?? services.localCachingClient.getSubject(id: item.assignment.subjectID)
        guard let subject = subject else { return nil }
        return SubjectRowData(id: subject.id, subject: subject, assignment: nil)
      }
      let title = level == currentLevel ? "Current level (\(level))" : "Level \(level)"
      groups.append(.init(title: title, rows: rows))
    }
    return (correct, incorrect, groups)
  }
}

/// Subject-detail destination used inside the review / lessons stacks.
@available(iOS 16.0, *)
private struct FlowSubjectDetail: View {
  let services: TKMServices
  let subjectID: Int64
  let delegate: SubjectDelegate

  var body: some View {
    if let subject = services.localCachingClient.getSubject(id: subjectID) {
      SubjectDetailContent(services: services, subject: subject,
                           studyMaterials: services.localCachingClient
                             .getStudyMaterial(subjectId: subjectID),
                           assignment: services.localCachingClient
                             .getAssignment(subjectId: subjectID),
                           task: nil, delegate: delegate)
        .navigationTitle(subject.japanese)
        .navigationBarTitleDisplayMode(.inline)
    } else {
      Text("Subject not found")
    }
  }
}

// MARK: - Review flow

@available(iOS 16.0, *)
final class ReviewFlowModel: NSObject, ObservableObject, SubjectDelegate {
  let services: TKMServices
  let isPracticeSession: Bool
  let onClose: () -> Void
  @Published var path = NavigationPath()
  @Published var reviewModel: ReviewViewModel
  @Published var summaryItems: [ReviewItem]?

  init(services: TKMServices, items: [ReviewItem], isPracticeSession: Bool,
       onClose: @escaping () -> Void) {
    self.services = services
    self.isPracticeSession = isPracticeSession
    self.onClose = onClose
    reviewModel = ReviewViewModel(services: services, items: items,
                                  isPracticeSession: isPracticeSession)
    super.init()
    reviewModel.onFinished = { [weak self] in self?.finish() }
  }

  private func finish() {
    // Practice sessions just close; real reviews end on the summary.
    if isPracticeSession { onClose() } else { summaryItems = reviewModel.session.completedReviews }
  }

  func reReview() {
    guard let items = summaryItems else { return }
    let incorrect = items.filter { $0.answer.meaningWrong || $0.answer.readingWrong }
      .map { ReviewItem(assignment: $0.assignment, subject: $0.subject) }
    guard !incorrect.isEmpty else { onClose()
      return
    }
    let model = ReviewViewModel(services: services, items: incorrect.shuffled(),
                                isPracticeSession: true)
    model.onFinished = { [weak self] in self?.onClose() }
    reviewModel = model
    summaryItems = nil
  }

  func didTapSubject(_ subject: TKMSubject) { path.append(subject.id) }
  func openPracticeReview(_: TKMSubject) {}
}

@available(iOS 16.0, *)
struct ReviewFlowView: View {
  @StateObject private var flow: ReviewFlowModel

  init(services: TKMServices, launch: ReviewLaunch, onClose: @escaping () -> Void) {
    _flow = StateObject(wrappedValue: ReviewFlowModel(services: services, items: launch.items,
                                                      isPracticeSession: launch.isPracticeSession,
                                                      onClose: onClose))
  }

  var body: some View {
    NavigationStack(path: $flow.path) {
      content
        .navigationDestination(for: Int64.self) { id in
          FlowSubjectDetail(services: flow.services, subjectID: id, delegate: flow)
        }
    }
  }

  @ViewBuilder private var content: some View {
    if let items = flow.summaryItems {
      ReviewSummaryView(services: flow.services, items: items,
                        onTapSubject: { flow.path.append($0.id) },
                        onReReview: { flow.reReview() }, onDone: flow.onClose)
    } else {
      ReviewScreen(model: flow.reviewModel, subjectDelegate: flow)
        .toolbar(.hidden, for: .navigationBar)
    }
  }
}

// MARK: - Lessons flow

@available(iOS 16.0, *)
final class LessonFlowModel: NSObject, ObservableObject, SubjectDelegate {
  let services: TKMServices
  let items: [ReviewItem]
  let subjects: [TKMSubject]
  let assignments: [TKMAssignment?]
  let onClose: () -> Void
  @Published var path = NavigationPath()
  @Published var quizModel: ReviewViewModel?
  @Published var summaryItems: [ReviewItem]?

  init(services: TKMServices, items: [ReviewItem], onClose: @escaping () -> Void) {
    self.services = services
    self.items = items
    self.onClose = onClose
    var subjects = [TKMSubject]()
    var assignments = [TKMAssignment?]()
    for item in items {
      let subject = item.subject ?? services.localCachingClient.getSubject(id: item.assignment
        .subjectID)
      guard let subject = subject else { continue }
      subjects.append(subject)
      assignments.append(item.assignment)
    }
    self.subjects = subjects
    self.assignments = assignments
    super.init()
  }

  func startQuiz() {
    let model = ReviewViewModel(services: services, items: items, isPracticeSession: false)
    model.onFinished = { [weak self] in self?.summaryItems = model.session.completedReviews }
    quizModel = model
  }

  func reReview() {
    guard let items = summaryItems else { return }
    let incorrect = items.filter { $0.answer.meaningWrong || $0.answer.readingWrong }
      .map { ReviewItem(assignment: $0.assignment, subject: $0.subject) }
    guard !incorrect.isEmpty else { onClose()
      return
    }
    let model = ReviewViewModel(services: services, items: incorrect.shuffled(),
                                isPracticeSession: true)
    model.onFinished = { [weak self] in self?.onClose() }
    quizModel = model
    summaryItems = nil
  }

  func didTapSubject(_ subject: TKMSubject) { path.append(subject.id) }
  func openPracticeReview(_: TKMSubject) {}
}

@available(iOS 16.0, *)
struct LessonFlowView: View {
  @StateObject private var flow: LessonFlowModel

  init(services: TKMServices, launch: LessonLaunch, onClose: @escaping () -> Void) {
    _flow = StateObject(wrappedValue: LessonFlowModel(services: services, items: launch.items,
                                                      onClose: onClose))
  }

  var body: some View {
    NavigationStack(path: $flow.path) {
      content
        .navigationDestination(for: Int64.self) { id in
          FlowSubjectDetail(services: flow.services, subjectID: id, delegate: flow)
        }
    }
  }

  @ViewBuilder private var content: some View {
    if let items = flow.summaryItems {
      ReviewSummaryView(services: flow.services, items: items,
                        onTapSubject: { flow.path.append($0.id) },
                        onReReview: { flow.reReview() }, onDone: flow.onClose)
    } else if let quiz = flow.quizModel {
      ReviewScreen(model: quiz, subjectDelegate: flow)
        .toolbar(.hidden, for: .navigationBar)
    } else {
      LessonsScreen(services: flow.services, subjects: flow.subjects, assignments: flow.assignments,
                    delegate: flow, onStartQuiz: { flow.startQuiz() })
        .navigationTitle("Lessons")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .navigationBarLeading) { Button("Close", action: flow.onClose) }
        }
    }
  }
}
