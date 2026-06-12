//
//  PulseBarStatusController.swift
//  PulseBar
//
//  Created by lingjhf on 2026/6/12.
//

import AppKit
import Combine

@MainActor
final class PulseBarAppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: PulseBarStatusController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusController = PulseBarStatusController()
    }
}

@MainActor
final class PulseBarStatusController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let monitor: SystemMetricsMonitor
    private let defaults: UserDefaults
    private let launchAtLoginService: any LaunchAtLoginServicing
    private let errorAlertHandler: @MainActor (Error) -> Void
    private let menu = NSMenu()
    private var cancellables: Set<AnyCancellable> = []

    init(
        monitor: SystemMetricsMonitor? = nil,
        defaults: UserDefaults = .standard,
        launchAtLoginService: (any LaunchAtLoginServicing)? = nil,
        errorAlertHandler: @escaping @MainActor (Error) -> Void = PulseBarStatusController.showLaunchAtLoginError
    ) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.monitor = monitor ?? SystemMetricsMonitor()
        self.defaults = defaults
        self.launchAtLoginService = launchAtLoginService ?? LaunchAtLoginService()
        self.errorAlertHandler = errorAlertHandler

        super.init()

        menu.delegate = self
        statusItem.menu = menu
        configureStatusButton()
        bindMonitor()
        updateStatusItem(metrics: self.monitor.metrics)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else {
            return
        }

        button.alignment = .center
        button.font = PulseBarStatusItemLayout.titleFont
        button.toolTip = "PulseBar"
    }

    private func bindMonitor() {
        monitor.$metrics
            .sink { [weak self] metrics in
                self?.updateStatusItem(metrics: metrics)
            }
            .store(in: &cancellables)
    }

    private func updateStatusItem(metrics: SystemMetrics) {
        let configuration = displayConfiguration

        statusItem.length = PulseBarStatusItemLayout.length(for: configuration)
        statusItem.button?.image = nil
        statusItem.button?.imagePosition = .noImage
        statusItem.button?.title = MenuBarTitleFormatter.fixedWidthTitle(
            for: metrics,
            configuration: configuration
        )
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        menu.addItem(toggleItem(
            title: "Show CPU",
            isOn: displayOptions.showsCPU,
            action: #selector(toggleCPU)
        ))
        menu.addItem(toggleItem(
            title: "Show Memory",
            isOn: displayOptions.showsMemory,
            action: #selector(toggleMemory)
        ))
        menu.addItem(toggleItem(
            title: "Show Network",
            isOn: displayOptions.showsNetwork,
            action: #selector(toggleNetwork)
        ))
        menu.addItem(launchAtLoginMenuItem())
        menu.addItem(.separator())

        menu.addItem(disabledItem("Display Format"))
        for mode in MenuBarDisplayMode.allCases {
            menu.addItem(displayModeMenuItem(mode))
        }
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit PulseBar",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func toggleItem(title: String, isOn: Bool, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = isOn ? .on : .off
        return item
    }

    private func launchAtLoginMenuItem() -> NSMenuItem {
        let itemState = LaunchAtLoginMenuFormatter.itemState(for: launchAtLoginService.status)
        let item = NSMenuItem(
            title: itemState.title,
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        item.target = self
        item.state = itemState.isChecked ? .on : .off
        return item
    }

    private func displayModeMenuItem(_ mode: MenuBarDisplayMode) -> NSMenuItem {
        let item = NSMenuItem(
            title: mode.title,
            action: #selector(setDisplayMode(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = mode.rawValue
        item.state = mode == displayMode ? .on : .off
        return item
    }

    @objc private func toggleCPU() {
        setDisplayPreference(!displayOptions.showsCPU, forKey: MetricDisplayPreferenceKey.showCPU)
    }

    @objc private func toggleMemory() {
        setDisplayPreference(!displayOptions.showsMemory, forKey: MetricDisplayPreferenceKey.showMemory)
    }

    @objc private func toggleNetwork() {
        setDisplayPreference(!displayOptions.showsNetwork, forKey: MetricDisplayPreferenceKey.showNetwork)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            let targetValue = LaunchAtLoginMenuFormatter.targetEnabledValue(
                for: launchAtLoginService.status
            )
            try launchAtLoginService.setEnabled(targetValue)
        } catch {
            errorAlertHandler(error)
        }

        rebuildMenu()
    }

    @objc private func setDisplayMode(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let mode = MenuBarDisplayMode(rawValue: rawValue)
        else {
            return
        }

        defaults.set(mode.rawValue, forKey: MetricDisplayPreferenceKey.displayMode)
        updateStatusItem(metrics: monitor.metrics)
        rebuildMenu()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func setDisplayPreference(_ value: Bool, forKey key: String) {
        defaults.set(value, forKey: key)
        updateStatusItem(metrics: monitor.metrics)
        rebuildMenu()
    }

    private var displayOptions: MetricDisplayOptions {
        MetricDisplayOptions(
            showsCPU: boolPreference(forKey: MetricDisplayPreferenceKey.showCPU, defaultValue: true),
            showsMemory: boolPreference(forKey: MetricDisplayPreferenceKey.showMemory, defaultValue: true),
            showsNetwork: boolPreference(forKey: MetricDisplayPreferenceKey.showNetwork, defaultValue: true)
        )
    }

    private var displayMode: MenuBarDisplayMode {
        guard
            let rawValue = defaults.string(forKey: MetricDisplayPreferenceKey.displayMode),
            let mode = MenuBarDisplayMode(rawValue: rawValue)
        else {
            return .standard
        }

        return mode
    }

    private var displayConfiguration: MenuBarDisplayConfiguration {
        MenuBarDisplayConfiguration(options: displayOptions, mode: displayMode)
    }

    private func boolPreference(forKey key: String, defaultValue: Bool) -> Bool {
        guard defaults.object(forKey: key) != nil else {
            return defaultValue
        }

        return defaults.bool(forKey: key)
    }

    private static func showLaunchAtLoginError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Launch at Login Failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

enum PulseBarStatusItemLayout {
    static let titleFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private static let horizontalPadding: CGFloat = 16

    static func length(for configuration: MenuBarDisplayConfiguration) -> CGFloat {
        let template = MenuBarTitleFormatter.fixedWidthTemplate(for: configuration)
        return ceil(
            NSAttributedString(
                string: template,
                attributes: [.font: titleFont]
            ).size().width + horizontalPadding
        )
    }
}
