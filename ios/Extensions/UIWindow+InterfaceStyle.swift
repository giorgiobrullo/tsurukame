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

extension UIWindow {
  /// Applies the user's saved `Settings.interfaceStyle` to every window. Call at launch and when
  /// the setting changes (the SwiftUI app has no AppDelegate to do this on bootstrap anymore).
  static func applySavedInterfaceStyle() {
    let style = Settings.interfaceStyle
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .forEach { $0.setInterfaceStyle(style) }
  }

  @objc func setInterfaceStyle(_ style: InterfaceStyle) {
    if #available(iOS 13.0, *) {
      switch style {
      case .system:
        self.overrideUserInterfaceStyle = .unspecified
      case .dark:
        self.overrideUserInterfaceStyle = .dark
      case .light:
        self.overrideUserInterfaceStyle = .light
      }
    }
  }
}
