//
//  LaunchAtLoginService.swift
//  PulseBar
//
//  Created by lingjhf on 2026/6/12.
//

import Foundation
import ServiceManagement

enum LaunchAtLoginStatus: Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

struct LaunchAtLoginMenuItemState: Equatable {
    var title: String
    var isChecked: Bool
}

enum LaunchAtLoginMenuFormatter {
    static func itemState(for status: LaunchAtLoginStatus) -> LaunchAtLoginMenuItemState {
        switch status {
        case .enabled:
            LaunchAtLoginMenuItemState(title: "Launch at Login", isChecked: true)
        case .requiresApproval:
            LaunchAtLoginMenuItemState(
                title: "Launch at Login (Approve in System Settings)",
                isChecked: false
            )
        case .notRegistered, .notFound:
            LaunchAtLoginMenuItemState(title: "Launch at Login", isChecked: false)
        }
    }

    static func targetEnabledValue(for status: LaunchAtLoginStatus) -> Bool {
        status != .enabled
    }
}

protocol LaunchAtLoginServicing {
    var status: LaunchAtLoginStatus { get }
    var isEnabled: Bool { get }

    func setEnabled(_ isEnabled: Bool) throws
}

struct LaunchAtLoginService: LaunchAtLoginServicing {
    private let manager: AppLoginItemManaging

    init(manager: AppLoginItemManaging = SystemAppLoginItemManager()) {
        self.manager = manager
    }

    var status: LaunchAtLoginStatus {
        manager.status
    }

    var isEnabled: Bool {
        status == .enabled
    }

    func setEnabled(_ isEnabled: Bool) throws {
        if isEnabled {
            try manager.register()
        } else {
            try manager.unregister()
        }
    }
}

protocol AppLoginItemManaging {
    var status: LaunchAtLoginStatus { get }

    func register() throws
    func unregister() throws
}

struct SystemAppLoginItemManager: AppLoginItemManaging {
    private let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
    }

    var status: LaunchAtLoginStatus {
        switch service.status {
        case .notRegistered:
            .notRegistered
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .notFound
        @unknown default:
            .notFound
        }
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }
}
