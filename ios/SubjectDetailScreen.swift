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

// SwiftUI standalone subject detail screen, replacing SubjectDetailsViewController. Reuses the
// wrapped SubjectDetailsView (same content as in lessons/reviews) with the subject's study
// materials and assignment so SRS stats show.

@available(iOS 15.0, *)
struct SubjectDetailScreen: View {
  let services: TKMServices
  let subject: TKMSubject
  let delegate: SubjectDelegate

  var body: some View {
    SubjectDetailContent(services: services,
                         subject: subject,
                         studyMaterials: services.localCachingClient
                           .getStudyMaterial(subjectId: subject.id),
                         assignment: services.localCachingClient
                           .getAssignment(subjectId: subject.id),
                         task: nil,
                         delegate: delegate)
      .ignoresSafeArea(edges: .bottom)
  }
}

@available(iOS 15.0, *)
final class SubjectDetailHostingController: UIHostingController<SubjectDetailScreen>,
  TKMViewController, SubjectDelegate {
  private let services: TKMServices

  var canSwipeToGoBack: Bool { true }

  init(services: TKMServices, subject: TKMSubject) {
    self.services = services
    super.init(rootView: SubjectDetailScreen(services: services, subject: subject,
                                             delegate: PlaceholderDetailDelegate()))
    title = subject.japanese
    rootView = SubjectDetailScreen(services: services, subject: subject, delegate: self)
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.isNavigationBarHidden = false
  }

  func didTapSubject(_ subject: TKMSubject) {
    navigationController?.pushViewController(SubjectDetailHostingController(services: services,
                                                                            subject: subject),
                                             animated: true)
  }
}

private final class PlaceholderDetailDelegate: NSObject, SubjectDelegate {
  func didTapSubject(_: TKMSubject) {}
}
