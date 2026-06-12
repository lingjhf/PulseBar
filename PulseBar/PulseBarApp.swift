//
//  PulseBarApp.swift
//  PulseBar
//
//  Created by lingjhf on 2026/6/12.
//

import SwiftUI

@main
struct PulseBarApp: App {
    @NSApplicationDelegateAdaptor(PulseBarAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
