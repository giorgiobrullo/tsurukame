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

// Shared SwiftUI building blocks for the native (multiplatform) rewrite. Every migrated screen
// reuses these so the look and the UIKit-bridging stay consistent. iOS 15+ (matches the rest of the
// SwiftUI surface).

/// Marker protocol the (modally-presented) hosting controllers conform to. Previously the custom
/// UINavigationController used `canSwipeToGoBack` to gate the interactive pop gesture; with the
/// NavigationStack backbone it's vestigial, but kept so the conformances stay valid.
protocol TKMViewController: AnyObject {
  var canSwipeToGoBack: Bool { get }
}

// MARK: - Brand colours

@available(iOS 15.0, *)
extension Color {
  /// The adaptive (light/dark) brand and chrome colours, bridged from `TKMStyle`. Computed so the
  /// underlying dynamic `UIColor` re-resolves for the current trait collection.
  static var tkmBackground: Color { Color(uiColor: TKMStyle.Color.background) }
  static var tkmCellBackground: Color { Color(uiColor: TKMStyle.Color.cellBackground) }
  static var tkmLabel: Color { Color(uiColor: TKMStyle.Color.label) }
  static var tkmTint: Color { Color(uiColor: TKMStyle.defaultTintColor) }
  static var tkmRadical: Color { Color(uiColor: TKMStyle.radicalColor2) }
  static var tkmKanji: Color { Color(uiColor: TKMStyle.kanjiColor2) }
  static var tkmVocabulary: Color { Color(uiColor: TKMStyle.vocabularyColor2) }
}

// MARK: - Card

@available(iOS 15.0, *)
struct CardModifier: ViewModifier {
  var cornerRadius: CGFloat = 16

  func body(content: Content) -> some View {
    content
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(16)
      .background(Color.tkmCellBackground)
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
  }
}

@available(iOS 15.0, *)
extension View {
  /// Wraps content in the standard inset card (cell-background fill, rounded corners).
  func tkmCard(cornerRadius: CGFloat = 16) -> some View {
    modifier(CardModifier(cornerRadius: cornerRadius))
  }
}

// MARK: - Section

@available(iOS 15.0, *)
struct TKMSectionLabel: View {
  let text: String
  init(_ text: String) { self.text = text }

  var body: some View {
    Text(text.uppercased())
      .font(.caption.weight(.semibold))
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// A titled section: an uppercased caption label above its content. Used by the manually-laid-out
/// screens (the dashboard); form-style screens use SwiftUI's own `Section` instead.
@available(iOS 15.0, *)
struct TKMSection<Content: View>: View {
  let title: String
  @ViewBuilder var content: Content

  init(_ title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      TKMSectionLabel(title)
      content
    }
  }
}

// MARK: - Navigation row

/// A tappable, card-style row (icon, title, optional trailing value, chevron). The standalone
/// counterpart to a `value1` table cell with a disclosure indicator.
@available(iOS 15.0, *)
struct TKMNavRow: View {
  let title: String
  var subtitle: String?
  let systemImage: String
  var tint: Color = .tkmTint
  let action: () -> Void

  init(_ title: String, subtitle: String? = nil, systemImage: String, tint: Color = .tkmTint,
       action: @escaping () -> Void) {
    self.title = title
    self.subtitle = subtitle
    self.systemImage = systemImage
    self.tint = tint
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: systemImage)
          .foregroundStyle(tint)
          .frame(width: 24)
        Text(title)
          .foregroundStyle(Color.tkmLabel)
        Spacer(minLength: 8)
        if let subtitle = subtitle {
          Text(subtitle)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.tertiary)
      }
      .padding(.vertical, 13)
      .padding(.horizontal, 16)
      .frame(maxWidth: .infinity)
      .background(Color.tkmCellBackground)
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Settings binding

/// Backs SwiftUI settings controls that read/write `Settings.*` (which is NSKeyedArchiver-backed,
/// so
/// `@AppStorage` can't bind to it directly). `bind` produces a two-way `Binding` and fires
/// `objectWillChange` on write so dependent rows in the same screen refresh.
@available(iOS 15.0, *)
final class SettingsStore: ObservableObject {
  func bind<Value>(_ get: @escaping @autoclosure () -> Value,
                   _ set: @escaping (Value) -> Void) -> Binding<Value> {
    Binding(get: get, set: { [weak self] newValue in
      self?.objectWillChange.send()
      set(newValue)
    })
  }

  /// Force a re-render (e.g. in `onAppear`) so values changed on a pushed sub-screen show on
  /// return.
  func refresh() { objectWillChange.send() }
}

// MARK: - Hosting

/// Generic bridge for pushing a SwiftUI screen onto the existing UIKit navigation stack. Conforms
/// to
/// `TKMViewController` so the custom swipe-back gesture keeps working, applies the standard
/// background, and shows the nav bar. Migrated screens are `TKMHostingController(title:rootView:)`.
@available(iOS 15.0, *)
final class TKMHostingController<Content: View>: UIHostingController<Content>, TKMViewController {
  var canSwipeToGoBack: Bool { true }

  init(title: String?, rootView: Content) {
    super.init(rootView: rootView)
    self.title = title
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = TKMStyle.Color.background
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.isNavigationBarHidden = false
  }
}
