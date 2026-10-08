import AppKit
import ApplicationServices
import ServiceManagement
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let enabledKey = "enabled"

    private let log = Logger(subsystem: "com.3fingers.app", category: "GestureEngine")
    private let engine = GestureEngine.shared
    private var statusItem: NSStatusItem!
    private var permissionTimer: Timer?

    private let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let permissionItem = NSMenuItem(title: "Grant Accessibility Access…", action: #selector(openAccessibilitySettings), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [Self.enabledKey: true])

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.menu = buildMenu()

        checkAccessibility(prompt: true)
        engine.setEnabled(UserDefaults.standard.bool(forKey: Self.enabledKey))
        updateIcon()

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)

        log.notice("3Fingers launched")
    }

    // MARK: - Menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        for item in [enabledItem, loginItem, permissionItem] { item.target = self }
        menu.addItem(enabledItem)
        menu.addItem(loginItem)
        menu.addItem(permissionItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit 3Fingers", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        enabledItem.state = engine.isEnabled ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        permissionItem.isHidden = AXIsProcessTrusted()
    }

    private func updateIcon() {
        let name = engine.isEnabled ? "hand.tap.fill" : "hand.tap"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "3Fingers")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.appearsDisabled = !engine.isEnabled
    }

    @objc private func toggleEnabled() {
        let enabled = !engine.isEnabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        engine.setEnabled(enabled)
        updateIcon()
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
                log.notice("Launch at Login disabled")
            } else {
                try service.register()
                log.notice("Launch at Login enabled")
            }
        } catch {
            log.error("Launch at Login failed: \(error.localizedDescription, privacy: .public)")
            if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        }
    }

    @objc private func openAccessibilitySettings() {
        checkAccessibility(prompt: true)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    // MARK: - Accessibility

    /// Posting synthetic clicks and rewriting physical clicks both require Accessibility access.
    /// Prompts once, then polls until access is granted so the event tap can be installed without a relaunch.
    private func checkAccessibility(prompt: Bool) {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            log.notice("Accessibility access granted")
            return
        }
        log.notice("Waiting for Accessibility access")
        guard permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard AXIsProcessTrusted() else { return }
                timer.invalidate()
                self?.permissionTimer = nil
                self?.log.notice("Accessibility access granted")
                self?.engine.installEventTapIfNeeded()
            }
        }
    }

    // MARK: - Sleep / wake

    @objc private func didWake(_ note: Notification) {
        // Multitouch devices stop delivering frames across sleep; re-enumerate once the HID stack is back.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [engine, log] in
            log.notice("System woke; restarting multitouch devices")
            engine.restartDevices()
        }
    }
}
