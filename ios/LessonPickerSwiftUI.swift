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

// SwiftUI rewrites of LessonOrderViewController (reorder the subject types taught first) and
// LessonPickerViewController (hand-pick which items to learn now).

// MARK: - Lesson order

@available(iOS 15.0, *)
struct LessonOrderScreen: View {
  @State private var order: [TKMSubject.TypeEnum]

  init() {
    _order = State(initialValue: Array(Settings.lessonOrder))
  }

  var body: some View {
    List {
      Section {
        ForEach(order, id: \.self) { type in
          Text(type.description)
        }
        .onMove { from, to in
          order.move(fromOffsets: from, toOffset: to)
          Settings.lessonOrder = order
        }
      } footer: {
        Text("Drag to choose the order new items are introduced in lessons.")
      }
    }
    .environment(\.editMode, .constant(.active))
  }
}

// MARK: - Lesson picker

@available(iOS 15.0, *)
final class LessonPickerModel: ObservableObject {
  struct Group: Identifiable {
    let id = UUID()
    let title: String
    let rows: [SubjectRowData]
  }

  let groups: [Group]
  private let itemsById: [Int64: ReviewItem]
  @Published var selected = Set<Int64>()

  init(services: TKMServices) {
    let assignments = services.localCachingClient.getNonExcludedAssignments()
    let items = ReviewItem.readyForLessons(assignments: assignments,
                                           localCachingClient: services.localCachingClient)
    var itemsById = [Int64: ReviewItem]()
    var byLevel = [Int32: (radicals: [SubjectRowData], kanji: [SubjectRowData],
                           vocab: [SubjectRowData])]()
    for item in items {
      let id = item.assignment.subjectID
      guard let subject = services.localCachingClient.getSubject(id: id) else { continue }
      itemsById[id] = item
      let row = SubjectRowData(id: id, subject: subject, assignment: item.assignment)
      var entry = byLevel[item.assignment.level] ?? ([], [], [])
      switch subject.subjectType {
      case .radical: entry.radicals.append(row)
      case .kanji: entry.kanji.append(row)
      case .vocabulary: entry.vocab.append(row)
      default: break
      }
      byLevel[item.assignment.level] = entry
    }
    self.itemsById = itemsById
    groups = byLevel.sorted { $0.key < $1.key }.map { level, entry in
      Group(title: "Level \(level)", rows: entry.radicals + entry.kanji + entry.vocab)
    }
  }

  func toggle(_ id: Int64) {
    if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
  }

  var selectedItems: [ReviewItem] { selected.compactMap { itemsById[$0] } }
}

@available(iOS 15.0, *)
struct LessonPickerScreen: View {
  @ObservedObject var model: LessonPickerModel
  let onBegin: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      List {
        ForEach(model.groups) { group in
          Section(group.title) {
            ForEach(group.rows) { row in
              SubjectRow(data: row) { _ in model.toggle(row.id) }
                .overlay(alignment: .trailing) {
                  if model.selected.contains(row.id) {
                    Image(systemName: "checkmark.circle.fill")
                      .foregroundStyle(.white)
                      .padding(.trailing, 12)
                  }
                }
            }
          }
        }
      }
      .listStyle(.plain)

      Button(action: onBegin) {
        Text(model.selected.isEmpty ? "Begin" : "Begin (\(model.selected.count))")
          .font(.headline)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 14)
      }
      .buttonStyle(.borderedProminent)
      .tint(Color(uiColor: TKMStyle.radicalColor2))
      .disabled(model.selected.isEmpty)
      .padding(16)
    }
    .background(Color.tkmBackground.ignoresSafeArea())
  }
}

@available(iOS 15.0, *)
final class LessonPickerHostingController: UIHostingController<LessonPickerScreen>,
  TKMViewController {
  private let services: TKMServices
  private let model: LessonPickerModel

  var canSwipeToGoBack: Bool { true }

  init(services: TKMServices) {
    self.services = services
    let model = LessonPickerModel(services: services)
    self.model = model
    super.init(rootView: LessonPickerScreen(model: model, onBegin: {}))
    title = "Lesson Picker"
    rootView = LessonPickerScreen(model: model, onBegin: { [weak self] in self?.begin() })
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.isNavigationBarHidden = false
  }

  private func begin() {
    let items = model.selectedItems
    guard !items.isEmpty else { return }
    navigationController?.pushViewController(LessonsHostingController(services: services,
                                                                      items: items),
                                             animated: true)
  }
}
