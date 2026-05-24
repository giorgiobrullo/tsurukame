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

import SwiftUI
import UIKit

// The SwiftUI app entry point. Replaces the old main.swift / UIApplicationMain + Navigation
// storyboard bootstrap. `AppDelegate` is kept (via UIApplicationDelegateAdaptor) for the app-level
// callbacks (background fetch, notifications, applinks, badge). The root is still the existing
// UIKit
// navigation stack, wrapped in a representable, because the screens that haven't been migrated yet
// navigate by pushing onto a UINavigationController. Once the whole app is SwiftUI this becomes a
// SwiftUI NavigationStack.
@main
struct TsurukameApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    WindowGroup {
      RootNavigationView(appDelegate: appDelegate)
        .ignoresSafeArea()
    }
  }
}

/// Hosts the app's root `UINavigationController` and hands it to `AppDelegate` to bootstrap
/// (decide login vs. main, apply the interface style).
struct RootNavigationView: UIViewControllerRepresentable {
  let appDelegate: AppDelegate

  func makeUIViewController(context _: Context) -> UINavigationController {
    let nav = StoryboardScene.Navigation.initialScene.instantiate()
    appDelegate.bootstrap(navigationController: nav)
    return nav
  }

  func updateUIViewController(_: UINavigationController, context _: Context) {}
}
