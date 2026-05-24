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

// SwiftUI rewrite of SearchResultViewController. The results controller must be a UIViewController
// conforming to UISearchResultsUpdating (UISearchController's requirement), so a hosting controller
// owns the search logic and feeds a SwiftUI list that reuses SubjectRow.

private let kMaxResults = 50

private func subjectMatchesQuery(_ subject: TKMSubject, query: String, kanaQuery: String) -> Bool {
  if subject.japanese.hasPrefix(query) { return true }
  for meaning in subject.meanings
    where meaning.meaning.lowercased().hasPrefix(query) { return true }
  for reading in subject.readings where reading.reading.hasPrefix(kanaQuery) { return true }
  return false
}

private func subjectMatchesQueryExactly(_ subject: TKMSubject, query: String,
                                        kanaQuery: String?) -> Bool {
  for meaning in subject.meanings where meaning.meaning.lowercased() == query { return true }
  if let kanaQuery = kanaQuery {
    for reading in subject.readings where reading.reading == kanaQuery { return true }
  }
  return false
}

@available(iOS 15.0, *)
final class SearchResultsModel: ObservableObject {
  @Published var results: [TKMSubject] = []
}

/// Filters + ranks subjects for a query. Shared by the legacy UISearchController results controller
/// and the SwiftUI `.searchable` dashboard search.
@available(iOS 15.0, *)
func searchSubjects(query rawQuery: String, in allSubjects: [TKMSubject]) -> [TKMSubject] {
  let query = rawQuery.lowercased()
  guard !query.isEmpty else { return [] }

  var convertedAllCharacters = true
  let kanaQuery = TKMConvertKanaText(query, &convertedAllCharacters)
  let exactKanaQuery: String? = convertedAllCharacters ? kanaQuery : nil

  var results = allSubjects.filter { subjectMatchesQuery($0, query: query, kanaQuery: kanaQuery) }
  // Exact matches first, then by level, so exact hits survive the kMaxResults trim.
  results.sort { a, b in
    let aExact = subjectMatchesQueryExactly(a, query: query, kanaQuery: exactKanaQuery)
    let bExact = subjectMatchesQueryExactly(b, query: query, kanaQuery: exactKanaQuery)
    if aExact != bExact { return aExact }
    return a.level < b.level
  }
  if results.count > kMaxResults { results.removeLast(results.count - kMaxResults) }
  return results
}

@available(iOS 15.0, *)
struct SubjectSearchScreen: View {
  @ObservedObject var model: SearchResultsModel
  let onTap: (TKMSubject) -> Void

  var body: some View {
    List {
      ForEach(model.results, id: \.id) { subject in
        SubjectRow(data: SubjectRowData(id: subject.id, subject: subject, assignment: nil),
                   onTap: onTap)
      }
    }
    .listStyle(.plain)
  }
}

@available(iOS 15.0, *)
final class SubjectSearchResultsController: UIHostingController<SubjectSearchScreen>,
  UISearchResultsUpdating {
  private let services: TKMServices
  private weak var delegate: SearchResultViewControllerDelegate?
  private let model: SearchResultsModel
  private var allSubjects: [TKMSubject]?
  private let queue = DispatchQueue(label: "tsurukame.search-results", qos: .userInitiated)

  init(services: TKMServices, delegate: SearchResultViewControllerDelegate) {
    self.services = services
    self.delegate = delegate
    let model = SearchResultsModel()
    self.model = model
    super.init(rootView: SubjectSearchScreen(model: model, onTap: { _ in }))
    rootView = SubjectSearchScreen(model: model, onTap: { [weak self] subject in
      self?.delegate?.searchResultSelected(subject: subject)
    })
    queue.async { [weak self] in self?.ensureLoaded() }
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func ensureLoaded() {
    if allSubjects == nil { allSubjects = services.localCachingClient.getAllSubjects() }
  }

  func updateSearchResults(for searchController: UISearchController) {
    let query = searchController.searchBar.text!.lowercased()
    queue.async { [weak self] in
      guard let self = self else { return }
      self.ensureLoaded()

      var convertedAllCharacters = true
      let kanaQuery = TKMConvertKanaText(query, &convertedAllCharacters)
      let exactKanaQuery: String? = convertedAllCharacters ? kanaQuery : nil

      var results = (self.allSubjects ?? []).filter {
        subjectMatchesQuery($0, query: query, kanaQuery: kanaQuery)
      }
      // Exact matches first, then by level, so exact hits survive the kMaxResults trim.
      results.sort { a, b in
        let aExact = subjectMatchesQueryExactly(a, query: query, kanaQuery: exactKanaQuery)
        let bExact = subjectMatchesQueryExactly(b, query: query, kanaQuery: exactKanaQuery)
        if aExact != bExact { return aExact }
        return a.level < b.level
      }
      if results.count > kMaxResults { results.removeLast(results.count - kMaxResults) }

      DispatchQueue.main.async {
        // Drop stale results if the query moved on while we were working.
        guard query == searchController.searchBar.text!.lowercased() else { return }
        self.model.results = results
      }
    }
  }
}
