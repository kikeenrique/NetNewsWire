//
//  FeedInspectorViewController.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 1/20/18.
//  Copyright © 2018 Ranchero Software. All rights reserved.
//

import AppKit
import Articles
import Account
import UserNotifications

final class WebFeedInspectorViewController: NSViewController, Inspector {

	@IBOutlet weak var iconView: IconView!
	@IBOutlet weak var nameTextField: NSTextField?
	@IBOutlet weak var homePageURLTextField: NSTextField?
	@IBOutlet weak var urlTextField: NSTextField?
	@IBOutlet weak var isNotifyAboutNewArticlesCheckBox: NSButton!
	@IBOutlet weak var isReaderViewAlwaysOnCheckBox: NSButton?
	@IBOutlet weak var healthStatusLabel: NSTextField?
	@IBOutlet weak var lastSuccessLabel: NSTextField?
	@IBOutlet weak var errorCountLabel: NSTextField?
	@IBOutlet weak var lastErrorLabel: NSTextField?

	private var feed: WebFeed? {
		didSet {
			if feed != oldValue {
				updateUI()
			}
		}
	}

	private var userNotificationSettings: UNNotificationSettings?

	// MARK: Inspector

	let isFallbackInspector = false
	var objects: [Any]? {
		didSet {
			renameWebFeedIfNecessary()
			updateFeed()
		}
	}
	var windowTitle: String = NSLocalizedString("Feed Inspector", comment: "Feed Inspector window title")

	func canInspect(_ objects: [Any]) -> Bool {
		return objects.count == 1 && objects.first is WebFeed
	}

	// MARK: NSViewController

	override func viewDidLoad() {
		updateUI()
		NotificationCenter.default.addObserver(self, selector: #selector(imageDidBecomeAvailable(_:)), name: .ImageDidBecomeAvailable, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(updateUI), name: .DidUpdateFeedPreferencesFromContextMenu, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(webFeedSettingDidChange(_:)), name: .WebFeedSettingDidChange, object: nil)
	}
	
	override func viewDidAppear() {
		updateNotificationSettings()
	}
	
	override func viewDidDisappear() {
		renameWebFeedIfNecessary()
	}
	
	// MARK: Actions
	@IBAction func isNotifyAboutNewArticlesChanged(_ sender: Any) {
		guard userNotificationSettings != nil else  {
			DispatchQueue.main.async {
				self.isNotifyAboutNewArticlesCheckBox.setNextState()
			}
			return
		}
		
		UNUserNotificationCenter.current().getNotificationSettings { (settings) in
			self.updateNotificationSettings()
			
			if settings.authorizationStatus == .denied {
				DispatchQueue.main.async {
					self.isNotifyAboutNewArticlesCheckBox.setNextState()
					self.showNotificationsDeniedError()
				}
			} else if settings.authorizationStatus == .authorized {
				DispatchQueue.main.async {
					self.feed?.isNotifyAboutNewArticles = (self.isNotifyAboutNewArticlesCheckBox?.state ?? .off) == .on ? true : false
				}
			} else {
				UNUserNotificationCenter.current().requestAuthorization(options: [.badge, .sound, .alert]) { (granted, error) in
					self.updateNotificationSettings()
					if granted {
						DispatchQueue.main.async {
							self.feed?.isNotifyAboutNewArticles = (self.isNotifyAboutNewArticlesCheckBox?.state ?? .off) == .on ? true : false
							NSApplication.shared.registerForRemoteNotifications()
						}
					} else {
						DispatchQueue.main.async {
							self.isNotifyAboutNewArticlesCheckBox.setNextState()
						}
					}
				}
			}
		}
	}
	
	@IBAction func isReaderViewAlwaysOnChanged(_ sender: Any) {
		feed?.isArticleExtractorAlwaysOn = (isReaderViewAlwaysOnCheckBox?.state ?? .off) == .on ? true : false
	}
	
	// MARK: Notifications

	@objc func imageDidBecomeAvailable(_ note: Notification) {
		updateImage()
	}

	@objc func webFeedSettingDidChange(_ note: Notification) {
		guard let feed = feed,
			  let noteWebFeed = note.object as? WebFeed,
			  feed == noteWebFeed,
			  let key = note.userInfo?[WebFeed.WebFeedSettingUserInfoKey] as? String else {
			return
		}

		if key == WebFeed.WebFeedSettingKey.consecutiveErrorCount {
			updateHealthSection()
		}
	}

}

extension WebFeedInspectorViewController: NSTextFieldDelegate {

	func controlTextDidEndEditing(_ note: Notification) {
		renameWebFeedIfNecessary()
	}
	
}

private extension WebFeedInspectorViewController {

	func updateFeed() {
		guard let objects = objects, objects.count == 1, let singleFeed = objects.first as? WebFeed else {
			feed = nil
			return
		}
		feed = singleFeed
	}

	
	@objc func updateUI() {
		updateImage()
		updateName()
		updateHomePageURL()
		updateFeedURL()
		updateNotifyAboutNewArticles()
		updateIsReaderViewAlwaysOn()
		updateHealthSection()
		windowTitle = feed?.nameForDisplay ?? NSLocalizedString("Feed Inspector", comment: "Feed Inspector window title")
		isReaderViewAlwaysOnCheckBox?.isEnabled = true
		view.needsLayout = true
	}

	func updateImage() {
		guard let feed = feed, let iconView = iconView else {
			return
		}
		iconView.iconImage = IconImageCache.shared.imageForFeed(feed)
	}

	func updateName() {
		guard let nameTextField = nameTextField else {
			return
		}

		let name = feed?.editedName ?? feed?.name ?? ""
		if nameTextField.stringValue != name {
			nameTextField.stringValue = name
		}
	}

	func updateHomePageURL() {
		homePageURLTextField?.stringValue = feed?.homePageURL ?? ""
	}

	func updateFeedURL() {
		urlTextField?.stringValue = feed?.url ?? ""
	}

	func updateNotifyAboutNewArticles() {
		isNotifyAboutNewArticlesCheckBox?.title = feed?.notificationDisplayName ?? NSLocalizedString("Show notifications for new articles", comment: "Show notifications for new articles")
		isNotifyAboutNewArticlesCheckBox?.state = (feed?.isNotifyAboutNewArticles ?? false) ? .on : .off
	}

	func updateIsReaderViewAlwaysOn() {
		isReaderViewAlwaysOnCheckBox?.state = (feed?.isArticleExtractorAlwaysOn ?? false) ? .on : .off
	}

	func updateNotificationSettings() {
		UNUserNotificationCenter.current().getNotificationSettings { (settings) in
			self.userNotificationSettings = settings
			if settings.authorizationStatus == .authorized {
				DispatchQueue.main.async {
					NSApplication.shared.registerForRemoteNotifications()
				}
			}
		}
	}

	func showNotificationsDeniedError() {
		let updateAlert = NSAlert()
		updateAlert.alertStyle = .informational
		updateAlert.messageText = NSLocalizedString("Enable Notifications", comment: "Notifications")
		updateAlert.informativeText = NSLocalizedString("To enable notifications, open Notifications in System Preferences, then find NetNewsWire in the list.", comment: "To enable notifications, open Notifications in System Preferences, then find NetNewsWire in the list.")
		updateAlert.addButton(withTitle: NSLocalizedString("Open System Preferences", comment: "Open System Preferences"))
		updateAlert.addButton(withTitle: NSLocalizedString("Close", comment: "Close"))
		let modalResponse = updateAlert.runModal()
		if modalResponse == .alertFirstButtonReturn {
			NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
		}
	}

	func renameWebFeedIfNecessary() {
		guard let feed = feed,
			  let account = feed.account,
			  let nameTextField = nameTextField,
			  feed.nameForDisplay != nameTextField.stringValue else {
			return
		}

		account.renameWebFeed(feed, to: nameTextField.stringValue) { [weak self] result in
			if case .failure(let error) = result {
				self?.presentError(error)
			} else {
				self?.windowTitle = feed.nameForDisplay
			}
		}
	}

	func updateHealthSection() {
		guard let feed = feed,
			  let healthStatusLabel = healthStatusLabel,
			  let lastSuccessLabel = lastSuccessLabel,
			  let errorCountLabel = errorCountLabel,
			  let lastErrorLabel = lastErrorLabel else {
			return
		}

		let errorCount = feed.consecutiveErrorCount

		// Status
		if errorCount == 0 {
			healthStatusLabel.stringValue = "Status: Healthy"
			healthStatusLabel.textColor = .systemGreen
		} else if errorCount >= 10 {
			healthStatusLabel.stringValue = "Status: Broken"
			healthStatusLabel.textColor = .systemRed
		} else if errorCount >= 3 {
			healthStatusLabel.stringValue = "Status: Not updating"
			healthStatusLabel.textColor = .systemOrange
		} else {
			healthStatusLabel.stringValue = "Status: Recent errors"
			healthStatusLabel.textColor = .systemYellow
		}

		// Last successful update
		if let lastSuccess = feed.lastSuccessfulCheckDate {
			let formatter = RelativeDateTimeFormatter()
			formatter.unitsStyle = .full
			let timeString = formatter.localizedString(for: lastSuccess, relativeTo: Date())
			lastSuccessLabel.stringValue = "Last successful update: \(timeString)"
		} else {
			lastSuccessLabel.stringValue = "Last successful update: Never"
		}

		// Error count
		errorCountLabel.stringValue = "Consecutive errors: \(errorCount)"

		// Last error message
		if let errorMessage = feed.lastErrorMessage {
			lastErrorLabel.stringValue = "Last error: \(errorMessage)"
		} else {
			lastErrorLabel.stringValue = ""
		}
	}

}
