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
import WaniKaniAPI

// JLPT / Jōyō coverage. WaniKani's data doesn't tag kanji with JLPT level or Jōyō grade, so we ship
// a static mapping (kanji_reference.json, derived from KANJIDIC2 via scriptin/kanji-data) and cross
// it with the user's progress. "Coverage" = of the kanji in a group, how many you've reached Guru+.

@available(iOS 15.0, *)
enum KanjiReference {
  /// One kanji's reference data: JLPT level (5 = N5 ... 1 = N1), Jōyō grade (1...6 elementary,
  /// 8 = secondary school), and newspaper frequency rank. Any field may be absent.
  struct Entry: Decodable {
    let j: Int? // JLPT (new): 5...1
    let g: Int? // Jōyō grade: 1...6, 8
    let f: Int? // frequency rank
  }

  /// kanji character -> entry. Empty if the bundled resource is missing.
  static let table: [String: Entry] = {
    guard let url = Bundle.main.url(forResource: "kanji_reference", withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) else {
      return [:]
    }
    return decoded
  }()

  @available(iOS 15.0, *)
  static func coverage(lcc: LocalCachingClient,
                       subjectsById: [Int64: TKMSubject]) -> [StatsModel.CoverageGroup] {
    guard !table.isEmpty else { return [] }

    var waniKaniKanji = Set<String>()
    for (_, subject) in subjectsById where subject.subjectType == .kanji {
      waniKaniKanji.insert(subject.japanese)
    }
    var guruKanji = Set<String>()
    for assignment in lcc.getAllAssignments()
      where !assignment.isLocked && assignment.srsStage.category >= .guru {
      if let s = subjectsById[assignment.subjectID], s.subjectType == .kanji {
        guruKanji.insert(s.japanese)
      }
    }

    func group(_ section: String, _ name: String, _ color: Color,
               where predicate: (Entry) -> Bool) -> StatsModel.CoverageGroup {
      var total = 0, taught = 0, passed = 0
      for (char, entry) in table where predicate(entry) {
        total += 1
        if waniKaniKanji.contains(char) { taught += 1 }
        if guruKanji.contains(char) { passed += 1 }
      }
      return .init(section: section, name: name, passed: passed, taught: taught, total: total,
                   color: color)
    }

    let jlptColor = Color(uiColor: TKMStyle.kanjiColor2)
    let joyoColor = Color(uiColor: TKMStyle.vocabularyColor2)

    var groups = [StatsModel.CoverageGroup]()
    // JLPT N5 (easiest) -> N1 (hardest).
    for (level, name) in [(5, "N5"), (4, "N4"), (3, "N3"), (2, "N2"), (1, "N1")] {
      groups.append(group("JLPT", name, jlptColor) { $0.j == level })
    }
    // Jōyō: elementary grades 1-6, then secondary (grade 8 in KANJIDIC).
    for grade in 1 ... 6 {
      groups.append(group("Jōyō", "Grade \(grade)", joyoColor) { $0.g == grade })
    }
    groups.append(group("Jōyō", "Secondary", joyoColor) { $0.g == 8 })
    return groups
  }
}
