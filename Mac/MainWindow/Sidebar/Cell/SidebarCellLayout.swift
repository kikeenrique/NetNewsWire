//
//  SidebarLayout.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 11/24/17.
//  Copyright © 2017 Ranchero Software. All rights reserved.
//

import AppKit
import RSCore

// image - title - errorIndicator - unreadCount

struct SidebarCellLayout {

	let faviconRect: CGRect
	let titleRect: CGRect
	let errorIndicatorRect: CGRect
	let unreadCountRect: CGRect

	init(appearance: SidebarCellAppearance, cellSize: NSSize, shouldShowImage: Bool, textField: NSTextField, unreadCountView: UnreadCountView, errorIndicatorView: NSImageView) {

		let bounds = NSRect(x: 0.0, y: 0.0, width: floor(cellSize.width), height: floor(cellSize.height))

		var rFavicon = NSRect.zero
		if shouldShowImage {
			rFavicon = NSRect(x: 0.0, y: 0.0, width: appearance.imageSize.width, height: appearance.imageSize.height)
			rFavicon = rFavicon.centeredVertically(in: bounds)
		}
		self.faviconRect = rFavicon

		let textFieldSize = SingleLineTextFieldSizer.size(for: textField.stringValue, font: textField.font!)

		var rTextField = NSRect(x: 0.0, y: 0.0, width: textFieldSize.width, height: textFieldSize.height)
		if shouldShowImage {
			rTextField.origin.x = NSMaxX(rFavicon) + appearance.imageMarginRight
		}
		rTextField = rTextField.centeredVertically(in: bounds)

		let unreadCountSize = unreadCountView.intrinsicContentSize
		let unreadCountIsHidden = unreadCountView.unreadCount < 1

		var rUnread = NSRect.zero
		if !unreadCountIsHidden {
			rUnread.size = unreadCountSize
			rUnread.origin.x = NSMaxX(bounds) - unreadCountSize.width
			rUnread = rUnread.centeredVertically(in: bounds)
		}
		self.unreadCountRect = rUnread

		// Error indicator appears before unread count
		let errorIndicatorIsHidden = errorIndicatorView.isHidden
		let errorIndicatorSize: CGFloat = 14.0  // SF Symbol size
		var rErrorIndicator = NSRect.zero
		if !errorIndicatorIsHidden {
			rErrorIndicator.size = NSSize(width: errorIndicatorSize, height: errorIndicatorSize)
			if !unreadCountIsHidden {
				rErrorIndicator.origin.x = NSMinX(rUnread) - errorIndicatorSize - 4.0  // 4pt spacing
			} else {
				rErrorIndicator.origin.x = NSMaxX(bounds) - errorIndicatorSize
			}
			rErrorIndicator = rErrorIndicator.centeredVertically(in: bounds)
		}
		self.errorIndicatorRect = rErrorIndicator

		// Adjust text field to not overlap error indicator or unread count
		var textFieldMaxX = NSMaxX(bounds)
		if !errorIndicatorIsHidden {
			textFieldMaxX = NSMinX(rErrorIndicator) - 4.0
		} else if !unreadCountIsHidden {
			textFieldMaxX = NSMinX(rUnread) - appearance.unreadCountMarginLeft
		}
		if NSMaxX(rTextField) > textFieldMaxX {
			rTextField.size.width = textFieldMaxX - NSMinX(rTextField)
		}

		self.titleRect = rTextField
	}
}
