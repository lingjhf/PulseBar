//
//  SystemMetrics.swift
//  PulseBar
//
//  Created by lingjhf on 2026/6/12.
//

import Foundation

struct SystemMetrics: Equatable {
    var cpuUsage: Double?
    var memoryUsedBytes: UInt64?
    var memoryTotalBytes: UInt64?
    var uploadBytesPerSecond: Double?
    var downloadBytesPerSecond: Double?
    var todayUploadBytes: UInt64? = nil
    var todayDownloadBytes: UInt64? = nil
    var sampledAt: Date

    static let empty = SystemMetrics(
        cpuUsage: nil,
        memoryUsedBytes: nil,
        memoryTotalBytes: nil,
        uploadBytesPerSecond: nil,
        downloadBytesPerSecond: nil,
        todayUploadBytes: nil,
        todayDownloadBytes: nil,
        sampledAt: Date()
    )

    static let preview = SystemMetrics(
        cpuUsage: 0.12,
        memoryUsedBytes: 8_900_000_000,
        memoryTotalBytes: 17_179_869_184,
        uploadBytesPerSecond: 120_000,
        downloadBytesPerSecond: 2_100_000,
        todayUploadBytes: 1_200_000_000,
        todayDownloadBytes: 8_400_000_000,
        sampledAt: Date()
    )
}

struct MetricDisplayOptions: Equatable {
    var showsCPU: Bool
    var showsMemory: Bool
    var showsNetwork: Bool

    var hasVisibleMetrics: Bool {
        showsCPU || showsMemory || showsNetwork
    }
}

enum MetricDisplayPreferenceKey {
    static let showCPU = "showCPUInMenuBar"
    static let showMemory = "showMemoryInMenuBar"
    static let showNetwork = "showNetworkInMenuBar"
    static let displayMode = "menuBarDisplayMode"
}

enum MenuBarDisplayMode: String, CaseIterable, Equatable {
    case standard
    case compact
    case networkOnly

    var title: String {
        switch self {
        case .standard:
            "Standard"
        case .compact:
            "Compact"
        case .networkOnly:
            "Network Only"
        }
    }
}

struct MenuBarDisplayConfiguration: Equatable {
    var options: MetricDisplayOptions
    var mode: MenuBarDisplayMode
}

struct CPUTicks: Equatable {
    var user: UInt64
    var system: UInt64
    var idle: UInt64
    var nice: UInt64
}

struct NetworkCounters: Equatable {
    var receivedBytes: UInt64
    var sentBytes: UInt64
    var sampledAt: Date
}

struct NetworkRates: Equatable {
    var downloadBytesPerSecond: Double
    var uploadBytesPerSecond: Double
}

struct DailyNetworkUsage: Equatable {
    var dayIdentifier: String
    var uploadBytes: UInt64
    var downloadBytes: UInt64
}

struct DailyNetworkUsageSnapshot: Equatable {
    var dayIdentifier: String
    var uploadBytes: UInt64
    var downloadBytes: UInt64
    var receivedCounterBytes: UInt64
    var sentCounterBytes: UInt64
}

protocol DailyNetworkUsageSnapshotStoring {
    func loadSnapshot() -> DailyNetworkUsageSnapshot?
    func saveSnapshot(_ snapshot: DailyNetworkUsageSnapshot)
}

struct MemoryPageStats: Equatable {
    var internalPages: UInt64
    var wiredPages: UInt64
    var compressorPages: UInt64
}

enum SystemMetricsCalculator {
    static func cpuUsage(current: CPUTicks, previous: CPUTicks?) -> Double? {
        guard let previous else {
            return nil
        }

        guard
            current.user >= previous.user,
            current.system >= previous.system,
            current.idle >= previous.idle,
            current.nice >= previous.nice
        else {
            return nil
        }

        let usedDelta = (current.user - previous.user)
            + (current.system - previous.system)
            + (current.nice - previous.nice)
        let idleDelta = current.idle - previous.idle
        let totalDelta = usedDelta + idleDelta

        guard totalDelta > 0 else {
            return nil
        }

        return Double(usedDelta) / Double(totalDelta)
    }

    static func networkRates(current: NetworkCounters, previous: NetworkCounters?) -> NetworkRates? {
        guard let previous else {
            return nil
        }

        let elapsed = current.sampledAt.timeIntervalSince(previous.sampledAt)
        guard
            elapsed > 0,
            current.receivedBytes >= previous.receivedBytes,
            current.sentBytes >= previous.sentBytes
        else {
            return nil
        }

        return NetworkRates(
            downloadBytesPerSecond: Double(current.receivedBytes - previous.receivedBytes) / elapsed,
            uploadBytesPerSecond: Double(current.sentBytes - previous.sentBytes) / elapsed
        )
    }

    static func memoryUsedBytes(
        stats: MemoryPageStats,
        pageSize: UInt64,
        totalBytes: UInt64
    ) -> UInt64? {
        guard pageSize > 0, totalBytes > 0 else {
            return nil
        }

        let usedPages = stats.internalPages + stats.wiredPages + stats.compressorPages
        let usedBytes = usedPages * pageSize

        return min(usedBytes, totalBytes)
    }

    static func dayIdentifier(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}

final class DailyNetworkUsageTracker {
    private var snapshot: DailyNetworkUsageSnapshot?
    private let store: any DailyNetworkUsageSnapshotStoring
    private let calendar: Calendar

    init(
        store: any DailyNetworkUsageSnapshotStoring = UserDefaultsDailyNetworkUsageSnapshotStore(),
        calendar: Calendar = .current
    ) {
        self.store = store
        self.calendar = calendar
        self.snapshot = store.loadSnapshot()
    }

    func update(current counters: NetworkCounters) -> DailyNetworkUsage {
        let dayIdentifier = SystemMetricsCalculator.dayIdentifier(
            for: counters.sampledAt,
            calendar: calendar
        )
        let previousSnapshot = snapshot?.dayIdentifier == dayIdentifier ? snapshot : nil
        var uploadBytes = previousSnapshot?.uploadBytes ?? 0
        var downloadBytes = previousSnapshot?.downloadBytes ?? 0

        if let previousSnapshot,
           counters.sentBytes >= previousSnapshot.sentCounterBytes,
           counters.receivedBytes >= previousSnapshot.receivedCounterBytes {
            uploadBytes = addingSaturated(
                uploadBytes,
                counters.sentBytes - previousSnapshot.sentCounterBytes
            )
            downloadBytes = addingSaturated(
                downloadBytes,
                counters.receivedBytes - previousSnapshot.receivedCounterBytes
            )
        }

        let nextSnapshot = DailyNetworkUsageSnapshot(
            dayIdentifier: dayIdentifier,
            uploadBytes: uploadBytes,
            downloadBytes: downloadBytes,
            receivedCounterBytes: counters.receivedBytes,
            sentCounterBytes: counters.sentBytes
        )
        snapshot = nextSnapshot
        store.saveSnapshot(nextSnapshot)

        return DailyNetworkUsage(
            dayIdentifier: dayIdentifier,
            uploadBytes: uploadBytes,
            downloadBytes: downloadBytes
        )
    }

    private func addingSaturated(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let result = lhs.addingReportingOverflow(rhs)
        return result.overflow ? .max : result.partialValue
    }
}

struct UserDefaultsDailyNetworkUsageSnapshotStore: DailyNetworkUsageSnapshotStoring {
    private enum Key {
        static let dayIdentifier = "dailyNetworkUsage.dayIdentifier"
        static let uploadBytes = "dailyNetworkUsage.uploadBytes"
        static let downloadBytes = "dailyNetworkUsage.downloadBytes"
        static let receivedCounterBytes = "dailyNetworkUsage.receivedCounterBytes"
        static let sentCounterBytes = "dailyNetworkUsage.sentCounterBytes"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadSnapshot() -> DailyNetworkUsageSnapshot? {
        guard let dayIdentifier = defaults.string(forKey: Key.dayIdentifier) else {
            return nil
        }

        return DailyNetworkUsageSnapshot(
            dayIdentifier: dayIdentifier,
            uploadBytes: uint64Value(forKey: Key.uploadBytes),
            downloadBytes: uint64Value(forKey: Key.downloadBytes),
            receivedCounterBytes: uint64Value(forKey: Key.receivedCounterBytes),
            sentCounterBytes: uint64Value(forKey: Key.sentCounterBytes)
        )
    }

    func saveSnapshot(_ snapshot: DailyNetworkUsageSnapshot) {
        defaults.set(snapshot.dayIdentifier, forKey: Key.dayIdentifier)
        defaults.set(String(snapshot.uploadBytes), forKey: Key.uploadBytes)
        defaults.set(String(snapshot.downloadBytes), forKey: Key.downloadBytes)
        defaults.set(String(snapshot.receivedCounterBytes), forKey: Key.receivedCounterBytes)
        defaults.set(String(snapshot.sentCounterBytes), forKey: Key.sentCounterBytes)
    }

    private func uint64Value(forKey key: String) -> UInt64 {
        guard let value = defaults.string(forKey: key) else {
            return 0
        }

        return UInt64(value) ?? 0
    }
}
