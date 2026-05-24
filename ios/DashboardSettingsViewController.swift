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
import UIKit

/// Settings for which widgets appear on the main dashboard.
class DashboardSettingsViewController: UITableViewController, TKMViewController {
  private var model: TableModel?

  var canSwipeToGoBack: Bool { true }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Dashboard"
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.isNavigationBarHidden = false
    rerender()
  }

  private func rerender() {
    let model = MutableTableModel(tableView: tableView)

    model.add(section: "Layout",
              footer: "The new SwiftUI dashboard is the in-progress native redesign. Turn it off to use the classic dashboard.")
    model.add(SwitchModelItem(style: .subtitle,
                              title: "New SwiftUI dashboard (beta)",
                              subtitle: "Native redesign of the home screen",
                              on: Settings.useSwiftUIDashboard) {
        Settings.useSwiftUIDashboard = $0.isOn
      })

    model.add(section: "Widgets",
              footer: "Choose which widgets appear on the main dashboard.")
    model.add(SwitchModelItem(style: .subtitle,
                              title: "Activity & streak",
                              subtitle: "Daily streak and a heatmap of reviews and lessons",
                              on: Settings.showActivityWidget) {
        Settings.showActivityWidget = $0.isOn
      })
    model.add(SwitchModelItem(style: .subtitle,
                              title: "Accuracy",
                              subtitle: "Lifetime review accuracy in the \"All levels\" section",
                              on: Settings.showAccuracyStat) { Settings.showAccuracyStat = $0.isOn
      })
    model.add(SwitchModelItem(style: .subtitle,
                              title: "Review forecast",
                              subtitle: "Chart of upcoming reviews over the next 24 hours",
                              on: Settings.showForecastChart) { Settings.showForecastChart = $0.isOn
      })
    model.add(SwitchModelItem(style: .subtitle,
                              title: "Previous level graph",
                              subtitle: "Keep showing the previous level until it's fully completed",
                              on: Settings
                                .showPreviousLevelGraph) { Settings.showPreviousLevelGraph = $0.isOn
      })

    model.add(section: "Catch-up",
              footer: "When you're behind, show reviews as a manageable batch (your review batch size) instead of the full backlog, and cap each session to that batch.")
    model.add(SwitchModelItem(style: .subtitle, title: "Catch-up mode",
                              subtitle: "Tackle a big backlog one batch at a time",
                              on: Settings.catchUpMode) { Settings.catchUpMode = $0.isOn })

    self.model = model
    model.reloadTable()
  }
}
