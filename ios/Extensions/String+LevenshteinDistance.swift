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

extension String {
  /// Damerau-Levenshtein edit distance to another string. Swift port of the original Objective-C
  /// `NSString` category; operates on UTF-16 code units to preserve the original behaviour.
  func levenshteinDistance(to other: String) -> Float {
    let a = Array(utf16)
    let b = Array(other.utf16)
    if a.isEmpty { return Float(b.count) }
    if b.isEmpty { return Float(a.count) }

    let n = a.count + 1
    let m = b.count + 1
    var d = [Int](repeating: 0, count: n * m)

    for k in 0 ..< n { d[k] = k }
    for k in 0 ..< m { d[k * n] = k }

    for i in 1 ..< n {
      for j in 1 ..< m {
        let cost = a[i - 1] == b[j - 1] ? 0 : 1
        d[j * n + i] = Swift.min(d[(j - 1) * n + i] + 1,
                                 d[j * n + i - 1] + 1,
                                 d[(j - 1) * n + i - 1] + cost)

        // Damerau transposition.
        if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
          d[j * n + i] = Swift.min(d[j * n + i], d[(j - 2) * n + i - 2] + cost)
        }
      }
    }

    return Float(d[n * m - 1])
  }
}
