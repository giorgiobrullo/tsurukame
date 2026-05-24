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
//
// WIP: this file is NOT yet part of any Xcode target — see TsurukameWidget/SETUP.md for the
// 3-step wiring once you're back at a Mac with Xcode. It reads the snapshot the app already
// writes via WidgetSharedData (so WidgetSharedData.swift must be a member of this widget target).

import SwiftUI
import WidgetKit

private let radicalBlue = Color(red: 0x00 / 255, green: 0x93 / 255, blue: 0xDD / 255)
private let kanjiPink = Color(red: 0xDD / 255, green: 0x00 / 255, blue: 0x93 / 255)
private let flameOrange = Color(red: 0xE6 / 255, green: 0x39 / 255, blue: 0x5B / 255)

struct TsurukameEntry: TimelineEntry {
  let date: Date
  let snapshot: WidgetSharedData.Snapshot?
}

struct TsurukameProvider: TimelineProvider {
  private var sample: WidgetSharedData.Snapshot {
    .init(lessons: 12, reviews: 42, level: 12, streak: 7, username: "you", updatedAt: Date())
  }

  func placeholder(in _: Context) -> TsurukameEntry {
    TsurukameEntry(date: Date(), snapshot: sample)
  }

  func getSnapshot(in _: Context, completion: @escaping (TsurukameEntry) -> Void) {
    completion(TsurukameEntry(date: Date(), snapshot: WidgetSharedData.read() ?? sample))
  }

  func getTimeline(in _: Context, completion: @escaping (Timeline<TsurukameEntry>) -> Void) {
    let entry = TsurukameEntry(date: Date(), snapshot: WidgetSharedData.read())
    // The app reloads the timeline whenever its data changes; this is just a fallback cadence.
    let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
      .addingTimeInterval(3600)
    completion(Timeline(entries: [entry], policy: .after(next)))
  }
}

private struct StatBlock: View {
  let count: Int
  let label: String
  let color: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("\(count)")
        .font(.system(size: 30, weight: .bold, design: .rounded))
        .foregroundStyle(color)
        .minimumScaleFactor(0.5)
        .lineLimit(1)
      Text(label.uppercased())
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.secondary)
    }
  }
}

struct TsurukameWidgetEntryView: View {
  var entry: TsurukameEntry
  @Environment(\.widgetFamily) private var family

  var body: some View {
    let s = entry.snapshot
    VStack(alignment: .leading, spacing: family == .systemSmall ? 8 : 10) {
      HStack(spacing: 6) {
        Text("Level \(s?.level ?? 0)")
          .font(.system(size: 13, weight: .bold))
        Spacer()
        if let streak = s?.streak, streak > 0 {
          Label("\(streak)", systemImage: "flame.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(flameOrange)
        }
      }

      Spacer(minLength: 0)

      HStack(spacing: family == .systemSmall ? 16 : 28) {
        StatBlock(count: s?.lessons ?? 0, label: "Lessons", color: radicalBlue)
        StatBlock(count: s?.reviews ?? 0, label: "Reviews", color: kanjiPink)
        if family != .systemSmall { Spacer() }
      }
    }
  }
}

@main
struct TsurukameWidget: Widget {
  let kind = "TsurukameWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: TsurukameProvider()) { entry in
      if #available(iOS 17.0, *) {
        TsurukameWidgetEntryView(entry: entry)
          .containerBackground(.fill.tertiary, for: .widget)
      } else {
        TsurukameWidgetEntryView(entry: entry)
          .padding()
      }
    }
    .configurationDisplayName("Tsurukame")
    .description("Your lessons, reviews, level and streak at a glance.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}
