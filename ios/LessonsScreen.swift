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

// SwiftUI rewrite of LessonsViewController: page through each new item's details (the teaching
// phase), then take the quiz, which reuses the SwiftUI review engine.

@available(iOS 15.0, *)
struct LessonsScreen: View {
  let services: TKMServices
  let subjects: [TKMSubject]
  let assignments: [TKMAssignment?]
  let delegate: SubjectDelegate
  let onStartQuiz: () -> Void

  @State private var page = 0

  private var totalPages: Int { subjects.count + 1 } // teaching pages + the quiz-start page.

  var body: some View {
    VStack(spacing: 0) {
      TabView(selection: $page) {
        ForEach(subjects.indices, id: \.self) { index in
          SubjectDetailsRepresentable(services: services,
                                      subject: subjects[index],
                                      studyMaterials: nil,
                                      assignment: assignments[index],
                                      task: nil,
                                      delegate: delegate)
            .tag(index)
        }
        quizStartPage
          .tag(subjects.count)
      }
      .tabViewStyle(.page(indexDisplayMode: .never))
      .animation(.default, value: page)

      bottomBar
    }
    .background(Color.tkmBackground.ignoresSafeArea())
  }

  private var quizStartPage: some View {
    VStack(spacing: 20) {
      Spacer()
      Image(systemName: "checkmark.seal.fill")
        .font(.system(size: 64))
        .foregroundStyle(Color(uiColor: TKMStyle.radicalColor2))
      Text("Ready to quiz")
        .font(.title2.weight(.bold))
      Text("You've studied \(subjects.count) item\(subjects.count == 1 ? "" : "s"). " +
        "Quiz yourself to start them in your reviews.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
      Button(action: onStartQuiz) {
        Text("Start quiz")
          .font(.headline)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 14)
      }
      .buttonStyle(.borderedProminent)
      .tint(Color(uiColor: TKMStyle.radicalColor2))
      .padding(.horizontal, 32)
      Spacer()
    }
  }

  private var bottomBar: some View {
    HStack {
      Button {
        withAnimation { page = max(page - 1, 0) }
      } label: {
        Image(systemName: "chevron.left")
      }
      .disabled(page == 0)

      Spacer()
      Text("\(min(page + 1, subjects.count)) / \(subjects.count)")
        .font(.caption.weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(.secondary)
      Spacer()

      if page < subjects.count {
        Button {
          withAnimation { page = min(page + 1, subjects.count) }
        } label: {
          Image(systemName: "chevron.right")
        }
      } else {
        Button("Quiz", action: onStartQuiz)
          .font(.subheadline.weight(.semibold))
      }
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 12)
  }
}

@available(iOS 15.0, *)
final class LessonsHostingController: UIHostingController<LessonsScreen>, TKMViewController,
  SubjectDelegate {
  private let services: TKMServices
  private let items: [ReviewItem]

  var canSwipeToGoBack: Bool { false }

  init(services: TKMServices, items: [ReviewItem]) {
    self.services = services
    self.items = items

    // Resolve a subject for every item up front.
    var subjects = [TKMSubject]()
    var assignments = [TKMAssignment?]()
    for item in items {
      let subject = item.subject
        ?? services.localCachingClient.getSubject(id: item.assignment.subjectID)
      guard let subject = subject else { continue }
      subjects.append(subject)
      assignments.append(item.assignment)
    }

    super.init(rootView: LessonsScreen(services: services, subjects: subjects,
                                       assignments: assignments,
                                       delegate: PlaceholderLessonsDelegate(),
                                       onStartQuiz: {}))
    title = "Lessons"
    rootView = LessonsScreen(services: services, subjects: subjects, assignments: assignments,
                             delegate: self, onStartQuiz: { [weak self] in self?.startQuiz() })
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.isNavigationBarHidden = false
  }

  private func startQuiz() {
    let vc = SwiftUIReviewHostingController(services: services, items: items,
                                            isPracticeSession: false)
    navigationController?.pushViewController(vc, animated: true)
  }

  func didTapSubject(_ subject: TKMSubject) {
    navigationController?.pushViewController(SubjectDetailHostingController(services: services,
                                                                            subject: subject),
                                             animated: true)
  }
}

private final class PlaceholderLessonsDelegate: NSObject, SubjectDelegate {
  func didTapSubject(_: TKMSubject) {}
}
