//
//  MainTimelineTitleView.swift
//  NetNewsWire-iOS
//
//  Created by Maurice Parker on 9/21/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import UIKit

final class MainTimelineTitleView: UIView {

	@IBOutlet var iconView: IconView?
	@IBOutlet var label: UILabel?
	@IBOutlet var unreadCountView: MainTimelineUnreadCountView?
	@IBOutlet var errorIndicatorView: UIImageView?

	var errorCount: Int = 0 {
		didSet {
			if errorCount != oldValue {
				updateErrorIndicator()
			}
		}
	}

	@available(iOS 13.4, *)
	private lazy var pointerInteraction: UIPointerInteraction = {
		UIPointerInteraction(delegate: self)
	}()

	override var accessibilityLabel: String? {
		set { }
		get {
			if let name = label?.text {
				let unreadLabel = NSLocalizedString("unread", comment: "Unread label for accessibility")
				return "\(name) \(unreadCountView?.unreadCount ?? 0) \(unreadLabel)"
			}
			else {
				return nil
			}
		}
	}

	func buttonize() {
		heightAnchor.constraint(equalToConstant: 40.0).isActive = true
		accessibilityTraits = .button
		if #available(iOS 13.4, *) {
			addInteraction(pointerInteraction)
		}
	}
	
	func debuttonize() {
		heightAnchor.constraint(equalToConstant: 40.0).isActive = true
		accessibilityTraits.remove(.button)
		if #available(iOS 13.4, *) {
			removeInteraction(pointerInteraction)
		}
	}

	private func updateErrorIndicator() {
		if errorCount >= 10 {
			// Red X for broken feeds (10+ errors)
			let config = UIImage.SymbolConfiguration(paletteColors: [.systemRed])
			errorIndicatorView?.image = UIImage(systemName: "xmark.circle.fill", withConfiguration: config)
			errorIndicatorView?.isHidden = false
		} else if errorCount >= 3 {
			// Yellow warning for problematic feeds (3-9 errors)
			let config = UIImage.SymbolConfiguration(paletteColors: [.systemYellow])
			errorIndicatorView?.image = UIImage(systemName: "exclamationmark.triangle.fill", withConfiguration: config)
			errorIndicatorView?.isHidden = false
		} else {
			// No indicator for healthy feeds (0-2 errors)
			errorIndicatorView?.isHidden = true
			errorIndicatorView?.image = nil
		}
	}

}

extension MainTimelineTitleView: UIPointerInteractionDelegate {
	
	@available(iOS 13.4, *)
	func pointerInteraction(_ interaction: UIPointerInteraction, styleFor region: UIPointerRegion) -> UIPointerStyle? {
		var rect = self.frame
		rect.origin.x = rect.origin.x - 10
		rect.size.width = rect.width + 20

		return UIPointerStyle(effect: .automatic(UITargetedPreview(view: self)), shape: .roundedRect(rect))
	}
	
}
