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
import WaniKaniAPI

// App-icon badge + upcoming-review local notifications. Moved out of AppDelegate; uses the modern
// UNUserNotificationCenter.setBadgeCount instead of the deprecated applicationIconBadgeNumber.

private let kMaxLocalNotifications = 64

@available(iOS 16.0, *)
enum NotificationScheduler {
  static func update(services: TKMServices) {
    guard Settings.notificationsAllReviews || Settings.notificationsBadging else { return }
    guard let lcc = services.localCachingClient else { return }

    let center = UNUserNotificationCenter.current()
    let user = lcc.getUserInfo()
    let reviewCount = lcc.availableReviewCount
    let upcomingReviews = lcc.upcomingReviews

    if user?.hasVacationStartedAt ?? false {
      center.setBadgeCount(0)
      return
    }

    WatchHelper.sharedInstance.updatedData(client: lcc)

    center.getNotificationSettings { settings in
      switch settings.authorizationStatus {
      case .authorized, .ephemeral, .provisional:
        break
      default:
        return
      }

      DispatchQueue.main.async {
        center.setBadgeCount(reviewCount)
        center.removeAllPendingNotificationRequests()

        let startDate = NSCalendar.current.nextDate(after: Date(),
                                                    matching: DateComponents(minute: 0, second: 0),
                                                    matchingPolicy: .nextTime)!
        let startInterval = startDate.timeIntervalSinceNow
        var cumulativeReviews = reviewCount
        var notificationsAdded = 0
        for hour in 0 ..< upcomingReviews.count {
          let reviews = upcomingReviews[hour]
          if reviews == 0 { continue }
          cumulativeReviews += reviews

          let triggerTimeInterval = startInterval + (Double(hour) * 60 * 60)
          if triggerTimeInterval <= 0 { continue }

          let content = UNMutableNotificationContent()
          if settings.alertSetting == .enabled, Settings.notificationsAllReviews {
            content.body = "\(cumulativeReviews) review\(cumulativeReviews == 1 ? "" : "s") " +
              "available (\(upcomingReviews[hour]) new)"
          }
          if settings.badgeSetting == .enabled, Settings.notificationsBadging {
            content.badge = NSNumber(value: cumulativeReviews)
          }
          if settings.soundSetting == .enabled, Settings.notificationSounds {
            content.sound = UNNotificationSound.default
          }

          let trigger = UNTimeIntervalNotificationTrigger(timeInterval: triggerTimeInterval,
                                                          repeats: false)
          center.add(UNNotificationRequest(identifier: "badge-\(hour)", content: content,
                                           trigger: trigger))
          notificationsAdded += 1
          if notificationsAdded >= kMaxLocalNotifications { break }
        }
      }
    }
  }
}
