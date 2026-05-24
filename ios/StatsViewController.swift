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
import SwiftUI
import UIKit
import WaniKaniAPI

struct StatsData {
  struct Stage: Identifiable {
    let id = UUID()
    let name: String
    let count: Int
    let color: Color
  }

  let streak: Int
  let accuracy: Double?
  let avgLevelUpDays: Double?
  let totalItems: Int
  let stages: [Stage]
}

@available(iOS 15.0, *)
struct StatsView: View {
  let data: StatsData

  private var maxStageCount: Int { max(data.stages.map(\.count).max() ?? 1, 1) }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        // Top summary tiles.
        HStack(spacing: 12) {
          summaryTile(value: "\(data.streak)", caption: "day streak",
                      systemImage: "flame.fill", tint: Color(uiColor: TKMStyle.explosionColor2))
          summaryTile(value: data.accuracy.map { "\(Int($0.rounded()))%" } ?? "–",
                      caption: "accuracy", systemImage: "target", tint: .green)
        }
        HStack(spacing: 12) {
          summaryTile(value: data.avgLevelUpDays.map { String(format: "%.1fd", $0) } ?? "–",
                      caption: "avg level-up", systemImage: "calendar",
                      tint: Color(uiColor: TKMStyle.radicalColor2))
          summaryTile(value: "\(data.totalItems)", caption: "items started",
                      systemImage: "square.stack.3d.up.fill",
                      tint: Color(uiColor: TKMStyle.vocabularyColor2))
        }

        // SRS stage breakdown.
        VStack(alignment: .leading, spacing: 10) {
          Text("SRS stages")
            .font(.headline)
          ForEach(data.stages) { stage in
            HStack(spacing: 10) {
              Text(stage.name)
                .font(.subheadline)
                .frame(width: 96, alignment: .leading)
              GeometryReader { geo in
                ZStack(alignment: .leading) {
                  Capsule().fill(Color.secondary.opacity(0.15))
                  Capsule().fill(stage.color)
                    .frame(width: max(geo.size.width * CGFloat(stage.count)
                        / CGFloat(maxStageCount), stage.count > 0 ? 6 : 0))
                }
              }
              .frame(height: 14)
              Text("\(stage.count)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
            }
          }
        }
        .padding(16)
        .background(Color(uiColor: TKMStyle.Color.cellBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      }
      .padding(16)
    }
  }

  private func summaryTile(value: String, caption: String, systemImage: String,
                           tint: Color) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Image(systemName: systemImage)
        .foregroundStyle(tint)
      Text(value)
        .font(.system(size: 28, weight: .bold, design: .rounded))
        .minimumScaleFactor(0.5)
        .lineLimit(1)
      Text(caption)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .background(Color(uiColor: TKMStyle.Color.cellBackground))
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
  }
}

class StatsViewController: UIViewController, TKMViewController {
  private var services: TKMServices!

  var canSwipeToGoBack: Bool { true }

  func setup(services: TKMServices) { self.services = services }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Statistics"
    view.backgroundColor = TKMStyle.Color.background

    guard #available(iOS 15.0, *) else { return }
    let host = UIHostingController(rootView: StatsView(data: makeData()))
    host.view.backgroundColor = .clear
    addChild(host)
    host.view.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(host.view)
    NSLayoutConstraint.activate([
      host.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
    ])
    host.didMove(toParent: self)
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.isNavigationBarHidden = false
  }

  @available(iOS 15.0, *)
  private func makeData() -> StatsData {
    let client = services.localCachingClient!
    let counts = client.srsStageCounts()
    let names = ["", "Apprentice 1", "Apprentice 2", "Apprentice 3", "Apprentice 4",
                 "Guru 1", "Guru 2", "Master", "Enlightened", "Burned"]
    var stages = [StatsData.Stage]()
    for stage in 1 ... 9 {
      let srsStage = SRSStage(rawValue: stage)
      let color = srsStage.map { TKMStyle.color(forSRSStageCategory: $0.category) } ?? .gray
      stages.append(StatsData.Stage(name: names[stage], count: counts[stage],
                                    color: Color(uiColor: color)))
    }
    let total = counts[1 ... 9].reduce(0, +)
    return StatsData(streak: client.reviewStreak, accuracy: client.overallAccuracy,
                     avgLevelUpDays: client.averageLevelUpInterval.map { $0 / 86400 },
                     totalItems: total, stages: stages)
  }
}
