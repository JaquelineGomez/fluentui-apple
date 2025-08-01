//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License.
//

#if canImport(FluentUI_common)
import FluentUI_common
#endif
import UIKit

// MARK: ShyHeaderView

/// "Hideable" header view for use in a navigation stack, appearing above a content view controller
/// Used to contain an accessory provided by the VC contained by the NavigatableShyContainerVC
/// This class in itself is fairly straightforward, defining a height and a containment layout
/// The animation around showing/hiding this view progressively is handled by its superview/superVC, an instance of ShyHeaderController
class ShyHeaderView: UIView, TokenizedControl {
    typealias TokenSetKeyType = EmptyTokenSet.Tokens
    public var tokenSet: EmptyTokenSet = .init()

    /// Defines all possible states of the header view's appearance
    ///
    /// - exposed: Fully showing header
    /// - exposing: partially showing header (defined by a progress fraction, 0.0 - 1.0)
    /// - concealed: fully concealed (hidden)
    enum Exposure: Equatable {
        case concealed
        case exposing(CGFloat)
        case exposed

        /// Returns the progress between concealed and exposed as a fraction of the possible states
        /// Values are represented as a fraction (0.5) not as a percentage (50.0)
        /// Concealed and fully exposed are represented as 0.0 and 1.0, respectively
        var progress: CGFloat {
            switch self {
            case .concealed:
                return 0.0
            case .exposing(let progress):
                return progress
            case .exposed:
                return 1.0
            }
        }

        /// Initializer accepting a progress value
        /// Values outside the range 0.0-1.0 will be adjusted
        ///
        /// - Parameter progress: progress of the exposure, represented as a fraction
        init(withProgress progress: CGFloat) {
            if progress <= 0.0 {
                self = .concealed
            } else if progress >= 1.0 {
                self = .exposed
            } else {
                self = .exposing(progress)
            }
        }
    }

    private struct Constants {
        static let contentHorizontalPadding: CGFloat = 16
        static let contentTopPadding: CGFloat = 6
        static let contentTopPaddingCompact: CGFloat = 10
        static let contentTopPaddingCompactForLargePhone: CGFloat = 0
        static let contentBottomPadding: CGFloat = 10
        static let contentBottomPaddingCompact: CGFloat = 6
        static let accessoryHeight: CGFloat = 36
        static let maxHeightNoAccessory: CGFloat = 56 - NavigationBarTokenSet.systemHeight  // navigation bar - design: 56, system: 44
        static let maxHeightNoAccessoryCompact: CGFloat = 44 - NavigationBarTokenSet.compactSystemHeight   // navigation bar - design: 44, system: 32
        static let maxHeightNoAccessoryCompactForLargePhone: CGFloat = 44 - NavigationBarTokenSet.systemHeight   // navigation bar - design: 44, system: 44
    }

    convenience init() {
        self.init(frame: .zero)
        tokenSet.registerOnUpdate(for: self) { [weak self] in
            self?.updateColors()
        }
        self.initSecondaryContentStackView()
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        guard let newWindow else {
            return
        }
        tokenSet.update(newWindow.fluentTheme)
        updateColors()
    }

    private var contentInsets: UIEdgeInsets {
        return UIEdgeInsets(top: contentTopInset, left: Constants.contentHorizontalPadding, bottom: contentBottomInset, right: Constants.contentHorizontalPadding)
    }
    private var contentTopInset: CGFloat {
        if traitCollection.verticalSizeClass == .compact {
            if navigationBarIsHidden {
                return contentBottomInset
            } else {
                return traitCollection.horizontalSizeClass == .compact ? Constants.contentTopPaddingCompact : Constants.contentTopPaddingCompactForLargePhone
            }
        } else {
            return Constants.contentTopPadding
        }
    }
    var contentBottomInset: CGFloat {
        return traitCollection.verticalSizeClass == .compact ? Constants.contentBottomPaddingCompact : Constants.contentBottomPadding
    }

    /// Header's current state
    var exposure: Exposure = .exposed {
        didSet {
            switch exposure {
            case .concealed:
                contentStackView.accessibilityElementsHidden = true
                if cancelsContentFirstRespondingOnHide {
                    accessoryView?.resignFirstResponder()
                }
            default:
                contentStackView.accessibilityElementsHidden = false
                return
            }
        }
    }

    /// The contained accessory view
    /// Setter removes previous value and inserts the new one into the content stack
    /// AccessoryContentViews are responsible for their own internal layouts
    /// They will be contained in a UIStackView that fills the width of the header
    var accessoryView: UIView? {
        willSet {
            accessoryView?.removeFromSuperview()
            contentStackView.removeFromSuperview()
            // When there is no accessoryView, the top anchor of the secondaryContentStackView should be equal to
            // the top anchor of the parent view.
            if let secondaryContentStackViewTopAnchorConstraint {
                NSLayoutConstraint.activate([
                    secondaryContentStackViewTopAnchorConstraint
                ])
            }
        }
        didSet {
            if let newContentView = accessoryView {
                initContentStackView()
                contentStackView.addArrangedSubview(newContentView)
            }
            maxHeightChanged?()
        }
    }

    var secondaryAccessoryView: UIView? {
        willSet {
            secondaryAccessoryView?.removeFromSuperview()
        }
        didSet {
            if let newContentView = secondaryAccessoryView {
                secondaryContentStackView.addArrangedSubview(newContentView)
            }
            maxHeightChanged?()
        }
    }

    var accessoryViewHeight: CGFloat {
        if accessoryView == nil {
            return maxHeightNoAccessory
        } else {
            return contentTopInset + Constants.accessoryHeight + contentBottomInset
        }
    }

    var secondaryAccessoryViewHeight: CGFloat {
        guard let secondaryAccessoryView else {
            return 0.0
        }

        let secondaryAccessoryViewSize = secondaryAccessoryView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        return secondaryAccessoryViewSize.height
    }

    var maxHeight: CGFloat {
        return accessoryViewHeight + secondaryAccessoryViewHeight
    }

    private var maxHeightNoAccessory: CGFloat {
        if traitCollection.verticalSizeClass == .compact {
            return traitCollection.horizontalSizeClass == .compact ? Constants.maxHeightNoAccessoryCompact : Constants.maxHeightNoAccessoryCompactForLargePhone
        }
        if traitCollection.horizontalSizeClass == .compact && parentController?.msfNavigationController?.msfNavigationBar.usesLeadingTitle == false {
            // This is a portrait phone with a system-style title, the navigation bar is already 44px tall
            return 0
        }
        return lockedInContractedState ? 0.0 : Constants.maxHeightNoAccessory
    }
    var maxHeightChanged: (() -> Void)?

    var lockedInContractedState: Bool = false
    weak var parentController: ShyHeaderController?
    weak var paddingView: UIView?

    var navigationBarIsHidden: Bool = false {
        didSet {
            if navigationBarIsHidden != oldValue {
                updateContentInsets()
            }
        }
    }
    var navigationBarStyle: NavigationBar.Style = .primary {
        didSet {
            updateShadowVisibility()
        }
    }
    var navigationBarShadow: NavigationBar.Shadow = .automatic {
        didSet {
            updateShadowVisibility()
        }
    }

    private func updateColors() {
        guard let parentController = parentController, let (_, actualItem) = parentController.msfNavigationController?.msfNavigationBar.actualStyleAndItem(for: parentController.navigationItem) else {
            return
        }
        let color = actualItem.fluentConfiguration.navigationBarColor(fluentTheme: tokenSet.fluentTheme)
        backgroundColor = color
        paddingView?.backgroundColor = color
    }

    private let contentStackView = UIStackView()
    private var contentStackViewHeightConstraint: NSLayoutConstraint?
    private let secondaryContentStackView = UIStackView()
    private var secondaryContentStackViewTopAnchorConstraint: NSLayoutConstraint?
    private let shadow = Separator()

    private var needsShadow: Bool {
        switch navigationBarShadow {
        case .automatic:
            return navigationBarStyle == .system && traitCollection.userInterfaceStyle != .dark
        case .alwaysHidden:
            return false
        }
    }
    private var showsShadow: Bool = false {
        didSet {
            if showsShadow == oldValue {
                return
            }
            if showsShadow {
                initShadow()
            } else {
                shadow.removeFromSuperview()
            }
        }
    }

    /// Whether the header should cancel its first responder status when it moves to the concealed state
    /// e.g. should cancel a search on scroll
    private var cancelsContentFirstRespondingOnHide: Bool = false

    @available(iOS, deprecated: 17.0)
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateContentInsets()
        updateShadowVisibility()
    }

    private func initContentStackView() {
        contentStackView.isLayoutMarginsRelativeArrangement = true
        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStackView)

        // When there is a accessoryView, the top anchor of the secondaryContentStackView should be equal to
        // the bottom anchor of contentStackView.
        if let secondaryContentStackViewTopAnchorConstraint {
            NSLayoutConstraint.deactivate([
                secondaryContentStackViewTopAnchorConstraint
            ])
        }

        let heightConstraint = contentStackView.heightAnchor.constraint(equalToConstant: accessoryViewHeight)
        contentStackViewHeightConstraint = heightConstraint
        NSLayoutConstraint.activate([
            contentStackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentStackView.topAnchor.constraint(equalTo: topAnchor),
            contentStackView.bottomAnchor.constraint(equalTo: secondaryContentStackView.topAnchor),
            heightConstraint
        ])
        updateContentInsets()
        contentStackView.addInteraction(UILargeContentViewerInteraction())
    }

    private func initSecondaryContentStackView() {
        secondaryContentStackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(secondaryContentStackView)
        let topAnchorConstraint = secondaryContentStackView.topAnchor.constraint(equalTo: topAnchor)
        secondaryContentStackViewTopAnchorConstraint = topAnchorConstraint
        NSLayoutConstraint.activate([
            secondaryContentStackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            secondaryContentStackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            topAnchorConstraint,
            secondaryContentStackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        secondaryContentStackView.addInteraction(UILargeContentViewerInteraction())
    }

    private func initShadow() {
        let shadowView = shadow
        shadowView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(shadowView)
        NSLayoutConstraint.activate([
            shadowView.leftAnchor.constraint(equalTo: leftAnchor),
            shadowView.rightAnchor.constraint(equalTo: rightAnchor),
            shadowView.topAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func updateContentInsets() {
        contentStackView.layoutMargins = contentInsets
        maxHeightChanged?()
    }

    private func updateShadowVisibility() {
        showsShadow = needsShadow
    }
}
