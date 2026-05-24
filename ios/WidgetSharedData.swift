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
import WidgetKit

/// A small snapshot of dashboard state shared with the Home Screen widget via an app group.
/// Compiled into both the app (which writes it) and the widget extension (which reads it).
enum WidgetSharedData {
  static let appGroup = "group.com.giorgiobrullo.tsurukame"
  private static let snapshotKey = "dashboardSnapshot"

  struct Snapshot: Codable {
    var lessons: Int
    var reviews: Int
    var level: Int
    var streak: Int
    var username: String
    var updatedAt: Date
  }

  private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

  static func write(_ snapshot: Snapshot) {
    guard let defaults = defaults, let data = try? JSONEncoder().encode(snapshot) else { return }
    defaults.set(data, forKey: snapshotKey)
    if #available(iOS 14.0, *) {
      WidgetCenter.shared.reloadAllTimelines()
    }
  }

  static func read() -> Snapshot? {
    guard let defaults = defaults, let data = defaults.data(forKey: snapshotKey) else { return nil }
    return try? JSONDecoder().decode(Snapshot.self, from: data)
  }
}
