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
import Network

/// Network-reachability monitor built on the modern Network framework (`NWPathMonitor`),
/// replacing the legacy Reachability CocoaPod. Keeps the same `isReachable()` /
/// `startNotifier()` / `stopNotifier()` surface the rest of the app already calls.
final class NetworkMonitor {
  private let queue = DispatchQueue(label: "com.tsurukame.network-monitor")
  private let lock = NSLock()
  private var monitor: NWPathMonitor?
  // Optimistically assume connectivity until the first path update arrives.
  private var reachable = true

  init() {
    startNotifier()
  }

  deinit {
    monitor?.cancel()
  }

  func startNotifier() {
    lock.lock()
    defer { lock.unlock() }
    guard monitor == nil else { return }
    let monitor = NWPathMonitor()
    monitor.pathUpdateHandler = { [weak self] path in
      guard let self = self else { return }
      self.lock.lock()
      self.reachable = path.status == .satisfied
      self.lock.unlock()
    }
    monitor.start(queue: queue)
    self.monitor = monitor
  }

  func stopNotifier() {
    lock.lock()
    defer { lock.unlock() }
    monitor?.cancel()
    monitor = nil
  }

  func isReachable() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return reachable
  }
}
