import SwiftUI

/// HealthPush design token system. Use these throughout the app
/// instead of hardcoded values so spacing, radii, and typography
/// stay consistent and can be tuned in one place.
enum HP {

    // MARK: - Spacing

    /// Spacing scale used for padding, stack spacing, and gaps.
    enum Spacing {
        /// 2 pt -- hairline gaps (e.g. between title and subtitle).
        static let xxs: CGFloat = 2

        /// 4 pt -- tight internal spacing.
        static let xs: CGFloat = 4

        /// 6 pt -- small gaps inside compact rows.
        static let sm: CGFloat = 6

        /// 8 pt -- standard small spacing.
        static let md: CGFloat = 8

        /// 10 pt -- between icon and label in buttons.
        static let mdLg: CGFloat = 10

        /// 12 pt -- default stack/list spacing.
        static let lg: CGFloat = 12

        /// 14 pt -- spacing between grouped elements.
        static let lgXl: CGFloat = 14

        /// 16 pt -- standard section padding.
        static let xl: CGFloat = 16

        /// 18 pt -- card interior padding.
        static let cardPadding: CGFloat = 18

        /// 20 pt -- prominent section padding.
        static let xxl: CGFloat = 20

        /// 24 pt -- hero/onboarding section padding.
        static let xxxl: CGFloat = 24

        /// 32 pt -- bottom safe-area / large section gaps.
        static let jumbo: CGFloat = 32
    }

    // MARK: - Radius

    /// Corner radius scale for rounded rectangles.
    enum Radius {
        /// 8 pt -- small icon badges.
        static let sm: CGFloat = 8

        /// 12 pt -- icon containers, small cards.
        static let md: CGFloat = 12

        /// 14 pt -- standard cards, buttons.
        static let card: CGFloat = 14

        /// 16 pt -- prominent cards, warning banners.
        static let lg: CGFloat = 16

        /// 18 pt -- sheet-style buttons, onboarding CTAs.
        static let sheet: CGFloat = 18

        /// 22 pt -- section card backgrounds.
        static let section: CGFloat = 22

        /// 28 pt -- hero banner.
        static let hero: CGFloat = 28
    }

    // MARK: - Typography

    /// Semantic font tokens.
    enum Typography {
        /// Large rounded hero text (onboarding titles).
        static let heroTitle: Font = .system(.title, design: .rounded, weight: .bold)

        /// Section titles in dashboards and lists.
        static let sectionTitle: Font = .headline

        /// Card titles / row titles.
        static let cardTitle: Font = .subheadline.weight(.semibold)

        /// Card body / secondary row text.
        static let cardBody: Font = .subheadline

        /// Small secondary labels.
        static let caption: Font = .caption

        /// Monospaced text for credentials / technical values.
        static let mono: Font = .system(.body, design: .monospaced)
    }
}
