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

/// A pair of large, tappable gradient cards at the top of the dashboard showing the number of
/// available lessons and reviews. The content layer stays vivid (full WaniKani brand colours); the
/// system chrome above it provides the Liquid Glass.
class DashboardActionCardsItem: TableModelItem {
  let lessonCount: Int
  let reviewCount: Int
  let lessonsEnabled: Bool
  let reviewsEnabled: Bool
  let lessonsSubtitle: String
  let reviewsSubtitle: String
  let onLessons: () -> Void
  let onReviews: () -> Void

  init(lessonCount: Int, reviewCount: Int,
       lessonsEnabled: Bool, reviewsEnabled: Bool,
       lessonsSubtitle: String, reviewsSubtitle: String,
       onLessons: @escaping () -> Void, onReviews: @escaping () -> Void) {
    self.lessonCount = lessonCount
    self.reviewCount = reviewCount
    self.lessonsEnabled = lessonsEnabled
    self.reviewsEnabled = reviewsEnabled
    self.lessonsSubtitle = lessonsSubtitle
    self.reviewsSubtitle = reviewsSubtitle
    self.onLessons = onLessons
    self.onReviews = onReviews
  }

  var cellFactory: TableModelCellFactory {
    .fromDefaultConstructor(cellClass: DashboardActionCardsCell.self)
  }

  var rowHeight: CGFloat? { 132 }
}

/// A single rounded gradient card with a title, a big count and a subtitle.
private class DashboardActionCard: UIView {
  private let gradient = GradientView(frame: .zero, colors: [])
  private let titleLabel = UILabel()
  private let countLabel = UILabel()
  private let subtitleLabel = UILabel()
  private let iconView = UIImageView()

  var tapHandler: (() -> Void)?
  private var isCardEnabled = true

  override init(frame: CGRect) {
    super.init(frame: frame)

    gradient.layer.cornerRadius = 16
    gradient.layer.cornerCurve = .continuous
    gradient.layer.startPoint = CGPoint(x: 0, y: 0)
    gradient.layer.endPoint = CGPoint(x: 1, y: 1)
    gradient.isUserInteractionEnabled = false
    addSubview(gradient)

    layer.cornerRadius = 16
    layer.cornerCurve = .continuous
    TKMStyle.addShadowToView(self, offset: 2, opacity: 0.2, radius: 4)

    titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
    titleLabel.textColor = UIColor.white.withAlphaComponent(0.9)

    countLabel.font = .systemFont(ofSize: 40, weight: .bold)
    countLabel.textColor = .white
    countLabel.adjustsFontSizeToFitWidth = true
    countLabel.minimumScaleFactor = 0.5

    subtitleLabel.font = .systemFont(ofSize: 12, weight: .regular)
    subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.85)

    iconView.tintColor = UIColor.white.withAlphaComponent(0.9)
    iconView.contentMode = .scaleAspectFit

    for v in [titleLabel, countLabel, subtitleLabel, iconView] {
      v.translatesAutoresizingMaskIntoConstraints = false
      v.isUserInteractionEnabled = false
      addSubview(v)
    }

    NSLayoutConstraint.activate([
      titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 14),
      titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),

      iconView.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
      iconView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      iconView.widthAnchor.constraint(equalToConstant: 22),
      iconView.heightAnchor.constraint(equalToConstant: 22),

      countLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      countLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      countLabel.bottomAnchor.constraint(equalTo: subtitleLabel.topAnchor, constant: -2),

      subtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      subtitleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      subtitleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
    ])

    // Use a tap gesture rather than UIControl touch-tracking so a vertical drag that starts on a
    // card scrolls the table cleanly instead of getting swallowed by the control.
    addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTap)))
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func layoutSubviews() {
    super.layoutSubviews()
    gradient.frame = bounds
  }

  func configure(title: String, count: Int, subtitle: String, symbol: String,
                 gradientColors: [CGColor], enabled: Bool) {
    titleLabel.text = title.uppercased()
    countLabel.text = "\(count)"
    subtitleLabel.text = subtitle
    iconView.image = UIImage(systemName: symbol)
    gradient.colors = gradientColors
    isCardEnabled = enabled
    isUserInteractionEnabled = enabled
    alpha = enabled ? 1.0 : 0.55
  }

  @objc private func didTap() {
    guard isCardEnabled else { return }
    // A quick tactile bounce on tap.
    UIView.animate(withDuration: 0.08, animations: {
      self.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)
    }, completion: { _ in
      UIView.animate(withDuration: 0.08) { self.transform = .identity }
    })
    tapHandler?()
  }
}

class DashboardActionCardsCell: TableModelCell {
  @TypedModelItem var item: DashboardActionCardsItem

  private let lessonsCard = DashboardActionCard()
  private let reviewsCard = DashboardActionCard()
  private let stack = UIStackView()

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    selectionStyle = .none
    backgroundColor = .clear
    let clearBackground = UIView()
    clearBackground.backgroundColor = .clear
    backgroundView = clearBackground

    stack.axis = .horizontal
    stack.distribution = .fillEqually
    stack.spacing = 12
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.addArrangedSubview(lessonsCard)
    stack.addArrangedSubview(reviewsCard)
    contentView.addSubview(stack)

    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
      stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
      stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
    ])
  }

  required init!(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func update() {
    lessonsCard.configure(title: "Lessons", count: item.lessonCount,
                          subtitle: item.lessonsSubtitle, symbol: "book.fill",
                          gradientColors: item.lessonsEnabled ? TKMStyle.radicalGradient
                            : TKMStyle.lockedGradient,
                          enabled: item.lessonsEnabled)
    lessonsCard.tapHandler = item.onLessons

    reviewsCard.configure(title: "Reviews", count: item.reviewCount,
                          subtitle: item.reviewsSubtitle, symbol: "rectangle.stack.fill",
                          gradientColors: item.reviewsEnabled ? TKMStyle.kanjiGradient
                            : TKMStyle.lockedGradient,
                          enabled: item.reviewsEnabled)
    reviewsCard.tapHandler = item.onReviews
  }
}
