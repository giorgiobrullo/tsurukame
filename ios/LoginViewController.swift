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

// The login UI is now SwiftUI (LoginScreen.swift). This file keeps the shared logout notification
// and the delegate contract that AppDelegate and the SwiftUI login use.

extension Notification.Name {
  static let logout = Notification.Name("kLogoutNotification")
}

protocol LoginViewControllerDelegate: AnyObject {
  func loginComplete()
}
