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
import UserNotifications

private let kBodyFontSize: CGFloat = UIFontDescriptor
  .preferredFontDescriptor(withTextStyle: .body).pointSize

// MARK: - Appearance

/// Visual settings that apply app-wide (pulled out of the old Reviews/AppSettings grab-bags).
class AppearanceSettingsViewController: UITableViewController, TKMViewController {
  private var services: TKMServices!
  private var model: TableModel?
  var canSwipeToGoBack: Bool { true }

  func setup(services: TKMServices) { self.services = services }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Appearance"
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.isNavigationBarHidden = false
    rerender()
  }

  private func rerender() {
    let model = MutableTableModel(tableView: tableView)
    model.addSection()
    if #available(iOS 13.0, *) {
      model.add(BasicModelItem(style: .value1, title: "Interface style",
                               subtitle: Settings.interfaceStyle.description,
                               accessoryType: .disclosureIndicator) { [unowned self] in
          self.navigationController?.pushViewController(makeInterfaceStyleViewController(),
                                                        animated: true)
        })
    }
    model.add(BasicModelItem(style: .default, title: "Fonts",
                             accessoryType: .disclosureIndicator) { [unowned self] in
        let vc = StoryboardScene.SelectFonts.initialScene.instantiate()
        vc.setup(services: self.services)
        self.navigationController?.pushViewController(vc, animated: true)
      })
    model.add(BasicModelItem(style: .value1, title: "Font size",
                             subtitle: Settings.fontSize != 0 ? "\(Int(Settings.fontSize * 100))%"
                               : "",
                             accessoryType: .disclosureIndicator) { [unowned self] in
        self.navigationController?.pushViewController(makeFontSizeViewController(), animated: true)
      })
    model.add(SwitchModelItem(style: .subtitle, title: "Show SRS level indicator", subtitle: nil,
                              on: Settings.showSRSLevelIndicator) {
        Settings.showSRSLevelIndicator = $0.isOn
      })
    self.model = model
    model.reloadTable()
  }
}

// MARK: - Audio

class AudioSettingsViewController: UITableViewController, TKMViewController {
  private var services: TKMServices!
  private var model: TableModel?
  var canSwipeToGoBack: Bool { true }

  func setup(services: TKMServices) { self.services = services }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Audio"
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.isNavigationBarHidden = false
    rerender()
  }

  private func rerender() {
    let model = MutableTableModel(tableView: tableView)
    model.addSection()
    model.add(SwitchModelItem(style: .subtitle, title: "Play audio automatically",
                              subtitle: "When you answer correctly",
                              on: Settings.playAudioAutomatically) {
        Settings.playAudioAutomatically = $0.isOn
      })
    model.add(SwitchModelItem(style: .subtitle, title: "Interrupt background audio",
                              subtitle: "When answer is played automatically",
                              on: Settings.interruptBackgroundAudio) {
        Settings.interruptBackgroundAudio = $0.isOn
      })
    model.add(BasicModelItem(style: .default, title: "Offline audio",
                             accessoryType: .disclosureIndicator) { [unowned self] in
        let vc = StoryboardScene.OfflineAudio.initialScene.instantiate()
        vc.setup(services: self.services)
        self.navigationController?.pushViewController(vc, animated: true)
      })
    self.model = model
    model.reloadTable()
  }
}

// MARK: - Anki mode

class AnkiSettingsViewController: UITableViewController, TKMViewController {
  private var model: TableModel?
  private var taskTypeIndexPath: IndexPath?
  private var combineIndexPath: IndexPath?
  var canSwipeToGoBack: Bool { true }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Anki mode"
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.isNavigationBarHidden = false
    rerender()
  }

  private func rerender() {
    if Settings.ankiModeTaskType != .both {
      Settings.ankiModeCombineReadingMeaning = false
    }
    let model = MutableTableModel(tableView: tableView)
    model.add(section: nil,
              footer: "Anki mode lets you do reviews without typing answers — reveal the answer and mark yourself right or wrong.")
    model.add(SwitchModelItem(style: .subtitle, title: "Anki mode",
                              subtitle: "Do reviews without typing answers",
                              on: Settings.ankiMode) { [unowned self] in self.ankiModeChanged($0) })
    taskTypeIndexPath = model.add(BasicModelItem(style: .value1, title: "Anki mode applies to",
                                                 subtitle: Settings.ankiModeTaskType.description,
                                                 accessoryType: .disclosureIndicator) {
                                    [unowned self] in
                                    self.navigationController?
                                      .pushViewController(makeAnkiModeTaskTypeViewController(),
                                                          animated: true)
                                  },
                                  hidden: !Settings.ankiMode)
    combineIndexPath = model
      .add(SwitchModelItem(style: .subtitle,
                           title: "Combine Reading + Meaning",
                           subtitle: "Only one review for reading and meaning with Anki mode enabled",
                           on: Settings.ankiModeCombineReadingMeaning) {
             Settings.ankiModeCombineReadingMeaning = $0.isOn
           },
           hidden: !Settings.ankiMode || Settings.ankiModeTaskType != .both)
    self.model = model
    model.reloadTable()
  }

  private func ankiModeChanged(_ switchView: UISwitch) {
    Settings.ankiMode = switchView.isOn
    Settings.ankiModeCombineReadingMeaning = false
    if let taskTypeIndexPath = taskTypeIndexPath {
      model?.setIndexPath(taskTypeIndexPath, hidden: !switchView.isOn)
    }
    if let combineIndexPath = combineIndexPath {
      model?.setIndexPath(combineIndexPath,
                          hidden: !switchView.isOn || Settings.ankiModeTaskType != .both)
    }
  }
}

// MARK: - Notifications

class NotificationsSettingsViewController: UITableViewController, TKMViewController {
  private var model: TableModel?
  private var notificationHandler: ((Bool) -> Void)?
  var canSwipeToGoBack: Bool { true }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Notifications"
    NotificationCenter.default.addObserver(self,
                                           selector: #selector(applicationDidBecomeActive(_:)),
                                           name: UIApplication.didBecomeActiveNotification,
                                           object: nil)
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.isNavigationBarHidden = false
    rerender()
  }

  private func rerender() {
    let model = MutableTableModel(tableView: tableView)
    model.addSection()
    model.add(SwitchModelItem(style: .default, title: "Notify for all available reviews",
                              subtitle: nil, on: Settings.notificationsAllReviews) {
        [unowned self] in
        self.promptForNotifications($0) { Settings.notificationsAllReviews = $0 }
      })
    model.add(SwitchModelItem(style: .default, title: "Badge the app icon", subtitle: nil,
                              on: Settings.notificationsBadging) { [unowned self] in
        self.promptForNotifications($0) { Settings.notificationsBadging = $0 }
      })
    model.add(SwitchModelItem(style: .default, title: "Play sound with notifications",
                              subtitle: nil,
                              on: Settings.notificationSounds) { [unowned self] in
        self.promptForNotifications($0) { Settings.notificationSounds = $0 }
      })
    self.model = model
    model.reloadTable()
  }

  private func promptForNotifications(_ switchView: UISwitch, handler: @escaping (Bool) -> Void) {
    if notificationHandler != nil { return }
    if !switchView.isOn {
      handler(false)
      UIApplication.shared.applicationIconBadgeNumber = 0
      return
    }
    switchView.setOn(false, animated: true)
    switchView.isEnabled = false
    notificationHandler = { granted in
      DispatchQueue.main.async {
        switchView.isEnabled = true
        switchView.setOn(granted, animated: true)
        handler(granted)
        self.notificationHandler = nil
      }
    }
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
      switch settings.authorizationStatus {
      case .authorized, .provisional, .ephemeral:
        self.notificationHandler?(true)
      case .notDetermined:
        center.requestAuthorization(options: [.badge, .alert, .sound]) { granted, _ in
          self.notificationHandler?(granted)
        }
      case .denied:
        DispatchQueue.main.async {
          UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!, options: [:],
                                    completionHandler: nil)
        }
      default:
        break
      }
    }
  }

  @objc private func applicationDidBecomeActive(_: NSNotification) {
    guard notificationHandler != nil else { return }
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      let granted = settings.authorizationStatus == .authorized || settings
        .authorizationStatus == .provisional
      self.notificationHandler?(granted)
    }
  }
}

// MARK: - Account

class AccountSettingsViewController: UITableViewController, TKMViewController {
  private var model: TableModel?
  var canSwipeToGoBack: Bool { true }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Account"
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.isNavigationBarHidden = false
    rerender()
  }

  private func rerender() {
    let model = MutableTableModel(tableView: tableView)

    model.add(section: "Custom Gravatar email address",
              footer: "Used to load your profile picture if it differs from your WaniKani email.")
    let gravatarItem =
      EditableTextModelItem(text: NSAttributedString(string: Settings.gravatarCustomEmail),
                            placeholderText: "Email address",
                            rightButtonImage: nil,
                            font: UIFont.systemFont(ofSize: kBodyFontSize),
                            autoCapitalizationType: .none,
                            maximumNumberOfLines: 1)
    gravatarItem.textChangedCallback = { Settings.gravatarCustomEmail = $0 }
    model.add(gravatarItem)

    model.addSection()
    let logOutItem = BasicModelItem(style: .default, title: "Log out", subtitle: nil,
                                    accessoryType: .none) { [unowned self] in self.didTapLogOut() }
    logOutItem.textColor = .systemRed
    model.add(logOutItem)

    self.model = model
    model.reloadTable()
  }

  private func didTapLogOut() {
    let c = UIAlertController(title: "Are you sure?", message: nil, preferredStyle: .alert)
    c.addAction(UIAlertAction(title: "Log out", style: .destructive) { _ in
      NotificationCenter.default.post(name: .logout, object: self)
    })
    c.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
    present(c, animated: true, completion: nil)
  }
}
