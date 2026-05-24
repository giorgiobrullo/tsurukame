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

class SettingsViewController: UITableViewController, TKMViewController {
  private var services: TKMServices!
  private var model: TableModel?
  private var versionIndexPath: IndexPath?
  private var notificationHandler: ((Bool) -> Void)?

  func setup(services: TKMServices) {
    self.services = services
  }

  // MARK: - TKMViewController

  var canSwipeToGoBack: Bool { true }

  // MARK: - UIViewController

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.isNavigationBarHidden = false
    rerender()
  }

  private func rerender() {
    let model = MutableTableModel(tableView: tableView, delegate: self)

    func addRow(_ title: String, symbol: String, tint: UIColor,
                handler: @escaping () -> Void) {
      let item = BasicModelItem(style: .default, title: title,
                                accessoryType: .disclosureIndicator, tapHandler: handler)
      item.image = UIImage(systemName: symbol)
      item.imageTintColor = tint
      model.add(item)
    }

    func push(_ makeVC: @escaping () -> UIViewController) -> () -> Void {
      { [unowned self] in self.navigationController?.pushViewController(makeVC(), animated: true) }
    }

    model.add(section: "Display")
    addRow("Appearance", symbol: "paintbrush.fill", tint: .systemPurple, handler: push {
      [unowned self] in
      let vc = AppearanceSettingsViewController(style: .grouped)
      vc.setup(services: self.services)
      return vc
    })
    addRow("Dashboard", symbol: "square.grid.2x2.fill", tint: .systemTeal,
           handler: push { DashboardSettingsViewController(style: .grouped) })

    model.add(section: "Study")
    addRow("Lessons", symbol: "book.fill", tint: TKMStyle.radicalColor1) { [unowned self] in
      self.perform(segue: StoryboardSegue.Settings.lessonSettings, sender: self)
    }
    addRow("Reviews", symbol: "rectangle.stack.fill",
           tint: TKMStyle.kanjiColor1) { [unowned self] in
      self.perform(segue: StoryboardSegue.Settings.reviewSettings, sender: self)
    }
    addRow("Anki mode", symbol: "square.on.square", tint: .systemIndigo,
           handler: push { AnkiSettingsViewController(style: .grouped) })
    addRow("Audio", symbol: "speaker.wave.2.fill", tint: .systemOrange, handler: push {
      [unowned self] in
      let vc = AudioSettingsViewController(style: .grouped)
      vc.setup(services: self.services)
      return vc
    })
    addRow("Subject info", symbol: "character.book.closed.fill",
           tint: TKMStyle.vocabularyColor1) { [unowned self] in
      self.perform(segue: StoryboardSegue.Settings.subjectDetailsSettings, sender: self)
    }

    model.add(section: "App")
    addRow("Notifications", symbol: "bell.badge.fill", tint: .systemRed,
           handler: push { NotificationsSettingsViewController(style: .grouped) })
    addRow("Account", symbol: "person.crop.circle.fill", tint: .systemBlue,
           handler: push { AccountSettingsViewController(style: .grouped) })

    model.add(section: "Diagnostics")
    if let coreVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
       let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
      let version = "\(coreVersion).\(build)"
      versionIndexPath = model
        .add(BasicModelItem(style: .value1, title: "Version", subtitle: version,
                            accessoryType: .none))
    }
    model.add(BasicModelItem(style: .subtitle,
                             title: "Export local database",
                             subtitle: "To attach to bug reports or email to the developer",
                             accessoryType: .disclosureIndicator) { [unowned self] in
        didTapSendBugReport()
      })
    model.add(BasicModelItem(style: .subtitle,
                             title: "Clear avatar image cache",
                             subtitle: "If you are having issues with your avatar not loading, try clearing the image cache.",
                             accessoryType: .none) { [unowned self] in didTapClearImageCache() })

    self.model = model
    model.reloadTable()
  }

  override func prepare(for segue: UIStoryboardSegue, sender _: Any?) {
    switch StoryboardSegue.Settings(segue) {
    case .reviewSettings:
      let vc = segue.destination as! ReviewSettingsViewController
      vc.setup(services: services)

    default:
      break
    }
  }

  // MARK: - UITableViewController

  override func tableView(_: UITableView, shouldShowMenuForRowAt indexPath: IndexPath) -> Bool {
    indexPath == versionIndexPath
  }

  override func tableView(_: UITableView, canPerformAction action: Selector, forRowAt _: IndexPath,
                          withSender _: Any?) -> Bool {
    action == #selector(copy(_:))
  }

  override func tableView(_ tableView: UITableView, performAction action: Selector,
                          forRowAt indexPath: IndexPath, withSender _: Any?) {
    if action == #selector(copy(_:)) {
      let cell = tableView.cellForRow(at: indexPath)
      UIPasteboard.general.string = cell?.detailTextLabel?.text
    }
  }

  // MARK: - Tap handlers

  private func didTapLogOut() {
    let c = UIAlertController(title: "Are you sure?", message: nil, preferredStyle: .alert)
    c.addAction(UIAlertAction(title: "Log out", style: .destructive, handler: { _ in
      NotificationCenter.default.post(name: .logout, object: self)
    }))
    c.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
    present(c, animated: true, completion: nil)
  }

  private func didTapSendBugReport() {
    let c = UIActivityViewController(activityItems: [LocalCachingClient.databaseUrl()],
                                     applicationActivities: nil)
    present(c, animated: true, completion: nil)
  }

  private func didTapClearImageCache() {
    HNKCache.shared().removeAllImages()
    let c = UIAlertController(title: "Image cache cleared", message: nil, preferredStyle: .alert)
    c.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
    present(c, animated: true, completion: nil)
  }
}
