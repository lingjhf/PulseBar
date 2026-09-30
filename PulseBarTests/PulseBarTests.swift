//
//  PulseBarTests.swift
//  PulseBarTests
//
//  Created by lingjhf on 2026/6/12.
//

import Foundation
import Testing
@testable import PulseBar

struct PulseBarTests {

    @Test func cpuUsageReturnsNilWithoutPreviousSample() {
        let usage = SystemMetricsCalculator.cpuUsage(
            current: CPUTicks(user: 10, system: 10, idle: 80, nice: 0),
            previous: nil
        )

        #expect(usage == nil)
    }

    @Test func cpuUsageCalculatesIdleFullAndPartialLoad() throws {
        let previous = CPUTicks(user: 100, system: 50, idle: 500, nice: 0)

        let idle = try #require(SystemMetricsCalculator.cpuUsage(
            current: CPUTicks(user: 100, system: 50, idle: 600, nice: 0),
            previous: previous
        ))
        #expect(idle == 0)

        let full = try #require(SystemMetricsCalculator.cpuUsage(
            current: CPUTicks(user: 150, system: 100, idle: 500, nice: 0),
            previous: previous
        ))
        #expect(full == 1)

        let partial = try #require(SystemMetricsCalculator.cpuUsage(
            current: CPUTicks(user: 120, system: 60, idle: 570, nice: 0),
            previous: previous
        ))
        #expect(abs(partial - 0.3) < 0.0001)
    }

    @Test func cpuUsageRejectsCounterReset() {
        let usage = SystemMetricsCalculator.cpuUsage(
            current: CPUTicks(user: 10, system: 10, idle: 10, nice: 0),
            previous: CPUTicks(user: 20, system: 10, idle: 10, nice: 0)
        )

        #expect(usage == nil)
    }

    @Test func networkRatesUseByteDeltasOverElapsedTime() throws {
        let previous = NetworkCounters(
            receivedBytes: 1_000,
            sentBytes: 500,
            sampledAt: Date(timeIntervalSince1970: 10)
        )
        let current = NetworkCounters(
            receivedBytes: 2_200,
            sentBytes: 1_100,
            sampledAt: Date(timeIntervalSince1970: 12)
        )

        let rates = try #require(SystemMetricsCalculator.networkRates(current: current, previous: previous))

        #expect(rates.downloadBytesPerSecond == 600)
        #expect(rates.uploadBytesPerSecond == 300)
    }

    @Test func networkRatesRejectInvalidSamples() {
        let previous = NetworkCounters(
            receivedBytes: 1_000,
            sentBytes: 500,
            sampledAt: Date(timeIntervalSince1970: 10)
        )

        let zeroElapsed = SystemMetricsCalculator.networkRates(
            current: NetworkCounters(
                receivedBytes: 1_100,
                sentBytes: 600,
                sampledAt: Date(timeIntervalSince1970: 10)
            ),
            previous: previous
        )
        #expect(zeroElapsed == nil)

        let counterReset = SystemMetricsCalculator.networkRates(
            current: NetworkCounters(
                receivedBytes: 900,
                sentBytes: 600,
                sampledAt: Date(timeIntervalSince1970: 11)
            ),
            previous: previous
        )
        #expect(counterReset == nil)
    }

    @Test func dailyNetworkUsageAccumulatesSameDayDeltas() {
        let tracker = DailyNetworkUsageTracker(
            store: FakeDailyNetworkUsageSnapshotStore(),
            calendar: utcCalendar
        )

        let first = tracker.update(current: NetworkCounters(
            receivedBytes: 1_000,
            sentBytes: 2_000,
            sampledAt: testDate(year: 2026, month: 6, day: 12, hour: 10)
        ))
        #expect(first == DailyNetworkUsage(
            dayIdentifier: "2026-06-12",
            uploadBytes: 0,
            downloadBytes: 0
        ))

        let second = tracker.update(current: NetworkCounters(
            receivedBytes: 1_900,
            sentBytes: 2_700,
            sampledAt: testDate(year: 2026, month: 6, day: 12, hour: 11)
        ))
        #expect(second == DailyNetworkUsage(
            dayIdentifier: "2026-06-12",
            uploadBytes: 700,
            downloadBytes: 900
        ))
    }

    @Test func dailyNetworkUsageHandlesCounterResetAndDayChange() {
        let tracker = DailyNetworkUsageTracker(
            store: FakeDailyNetworkUsageSnapshotStore(),
            calendar: utcCalendar
        )

        _ = tracker.update(current: NetworkCounters(
            receivedBytes: 1_000,
            sentBytes: 2_000,
            sampledAt: testDate(year: 2026, month: 6, day: 12, hour: 10)
        ))
        _ = tracker.update(current: NetworkCounters(
            receivedBytes: 2_000,
            sentBytes: 3_500,
            sampledAt: testDate(year: 2026, month: 6, day: 12, hour: 11)
        ))

        let counterReset = tracker.update(current: NetworkCounters(
            receivedBytes: 200,
            sentBytes: 300,
            sampledAt: testDate(year: 2026, month: 6, day: 12, hour: 12)
        ))
        #expect(counterReset == DailyNetworkUsage(
            dayIdentifier: "2026-06-12",
            uploadBytes: 1_500,
            downloadBytes: 1_000
        ))

        let nextDay = tracker.update(current: NetworkCounters(
            receivedBytes: 500,
            sentBytes: 900,
            sampledAt: testDate(year: 2026, month: 6, day: 13, hour: 1)
        ))
        #expect(nextDay == DailyNetworkUsage(
            dayIdentifier: "2026-06-13",
            uploadBytes: 0,
            downloadBytes: 0
        ))
    }

    @Test func dailyNetworkUsageResumesFromStoredSnapshot() {
        let store = FakeDailyNetworkUsageSnapshotStore(snapshot: DailyNetworkUsageSnapshot(
            dayIdentifier: "2026-06-12",
            uploadBytes: 10_000,
            downloadBytes: 20_000,
            receivedCounterBytes: 100_000,
            sentCounterBytes: 200_000
        ))
        let tracker = DailyNetworkUsageTracker(store: store, calendar: utcCalendar)

        let usage = tracker.update(current: NetworkCounters(
            receivedBytes: 101_500,
            sentBytes: 202_000,
            sampledAt: testDate(year: 2026, month: 6, day: 12, hour: 12)
        ))

        #expect(usage == DailyNetworkUsage(
            dayIdentifier: "2026-06-12",
            uploadBytes: 12_000,
            downloadBytes: 21_500
        ))
        #expect(store.snapshot?.sentCounterBytes == 202_000)
        #expect(store.snapshot?.receivedCounterBytes == 101_500)
    }

    @Test func memoryUsedBytesExcludesReclaimableCache() throws {
        let usedBytes = try #require(SystemMetricsCalculator.memoryUsedBytes(
            stats: MemoryPageStats(
                internalPages: 300,
                wiredPages: 120,
                compressorPages: 80
            ),
            pageSize: 16_384,
            totalBytes: 16_384_000
        ))

        #expect(usedBytes == 8_192_000)
    }

    @Test func memoryUsedBytesRejectsInvalidInputsAndClampsToTotal() throws {
        #expect(SystemMetricsCalculator.memoryUsedBytes(
            stats: MemoryPageStats(internalPages: 1, wiredPages: 1, compressorPages: 1),
            pageSize: 0,
            totalBytes: 16_384_000
        ) == nil)

        let usedBytes = try #require(SystemMetricsCalculator.memoryUsedBytes(
            stats: MemoryPageStats(
                internalPages: 1_000,
                wiredPages: 1_000,
                compressorPages: 1_000
            ),
            pageSize: 16_384,
            totalBytes: 16_384_000
        ))

        #expect(usedBytes == 16_384_000)
    }

    @Test func launchAtLoginMenuStateReflectsSystemStatus() {
        #expect(LaunchAtLoginMenuFormatter.itemState(for: .enabled) == LaunchAtLoginMenuItemState(
            title: "Launch at Login",
            isChecked: true
        ))
        #expect(LaunchAtLoginMenuFormatter.itemState(for: .notRegistered) == LaunchAtLoginMenuItemState(
            title: "Launch at Login",
            isChecked: false
        ))
        #expect(LaunchAtLoginMenuFormatter.itemState(for: .requiresApproval) == LaunchAtLoginMenuItemState(
            title: "Launch at Login (Approve in System Settings)",
            isChecked: false
        ))
        #expect(LaunchAtLoginMenuFormatter.itemState(for: .notFound) == LaunchAtLoginMenuItemState(
            title: "Launch at Login",
            isChecked: false
        ))

        #expect(!LaunchAtLoginMenuFormatter.targetEnabledValue(for: .enabled))
        #expect(LaunchAtLoginMenuFormatter.targetEnabledValue(for: .notRegistered))
        #expect(LaunchAtLoginMenuFormatter.targetEnabledValue(for: .requiresApproval))
        #expect(LaunchAtLoginMenuFormatter.targetEnabledValue(for: .notFound))
    }

    @Test func launchAtLoginServiceCallsRegisterAndUnregister() throws {
        let manager = FakeAppLoginItemManager(status: .notRegistered)
        let service = LaunchAtLoginService(manager: manager)

        #expect(service.status == .notRegistered)
        #expect(!service.isEnabled)

        try service.setEnabled(true)
        #expect(manager.registerCallCount == 1)
        #expect(manager.unregisterCallCount == 0)
        #expect(service.status == .enabled)
        #expect(service.isEnabled)

        try service.setEnabled(false)
        #expect(manager.registerCallCount == 1)
        #expect(manager.unregisterCallCount == 1)
        #expect(service.status == .notRegistered)
        #expect(!service.isEnabled)
    }

    @Test func launchAtLoginServicePreservesStatusWhenOperationFails() throws {
        let manager = FakeAppLoginItemManager(status: .notRegistered)
        manager.registerError = LaunchAtLoginTestError.operationFailed
        let service = LaunchAtLoginService(manager: manager)

        do {
            try service.setEnabled(true)
        } catch let error as LaunchAtLoginTestError {
            #expect(error == .operationFailed)
        }

        #expect(manager.registerCallCount == 1)
        #expect(manager.unregisterCallCount == 0)
        #expect(service.status == .notRegistered)
        #expect(!service.isEnabled)
    }

    @Test func metricFormattingCoversRatesMemoryAndPercentages() {
        #expect(MetricValueFormatter.byteRate(512) == "512B/s")
        #expect(MetricValueFormatter.byteRate(1_536) == "1.5KB/s")
        #expect(MetricValueFormatter.byteRate(2_097_152) == "2.0MB/s")
        #expect(MetricValueFormatter.byteAmount(1_073_741_824) == "1.0GB")
        #expect(MetricValueFormatter.byteAmount(nil) == "--")
        #expect(MetricValueFormatter.compactMemory(8_589_934_592) == "8.0G")
        #expect(MetricValueFormatter.memorySummary(
            usedBytes: 8_589_934_592,
            totalBytes: 17_179_869_184
        ) == "8.0GB / 16.0GB")
        #expect(MetricValueFormatter.percentage(0.124) == "12%")
        #expect(MetricValueFormatter.percentage(nil) == "--")
        #expect(MetricValueFormatter.thermalState(.nominal) == "OK")
        #expect(MetricValueFormatter.thermalState(.fair) == "WARM")
        #expect(MetricValueFormatter.thermalState(.serious) == "HOT")
        #expect(MetricValueFormatter.thermalState(.critical) == "CRIT")
        #expect(MetricValueFormatter.thermalState(.unknown) == "--")
        #expect(MetricValueFormatter.thermalState(nil) == "--")
    }

    @Test func menuBarMetricFormattingCoversUnitsAndPlaceholders() {
        #expect(MenuBarMetricFormatter.cpuWidthTemplate == "CPU 100%")
        #expect(MenuBarMetricFormatter.memoryWidthTemplate == "MEM 999.9G")
        #expect(MenuBarMetricFormatter.uploadWidthTemplate == "↑999.9G")
        #expect(MenuBarMetricFormatter.downloadWidthTemplate == "↓999.9G")
        #expect(MenuBarMetricFormatter.thermalStateWidthTemplate == "THM WARM")

        #expect(MenuBarMetricFormatter.cpu(0.997) == "CPU 100%")
        #expect(MenuBarMetricFormatter.cpu(nil) == "CPU --")
        #expect(MenuBarMetricFormatter.memory(8_589_934_592) == "MEM 8.0G")
        #expect(MenuBarMetricFormatter.memory(nil) == "MEM --")

        #expect(MenuBarMetricFormatter.upload(512) == "↑512B")
        #expect(MenuBarMetricFormatter.upload(1_536) == "↑1.5K")
        #expect(MenuBarMetricFormatter.upload(2_097_152) == "↑2.0M")
        #expect(MenuBarMetricFormatter.upload(1_073_741_824) == "↑1.0G")
        #expect(MenuBarMetricFormatter.upload(nil) == "↑--")

        #expect(MenuBarMetricFormatter.download(512) == "↓512B")
        #expect(MenuBarMetricFormatter.download(1_536) == "↓1.5K")
        #expect(MenuBarMetricFormatter.download(2_097_152) == "↓2.0M")
        #expect(MenuBarMetricFormatter.download(1_073_741_824) == "↓1.0G")
        #expect(MenuBarMetricFormatter.download(nil) == "↓--")

        #expect(MenuBarMetricFormatter.thermalState(.nominal) == "THM OK")
        #expect(MenuBarMetricFormatter.thermalState(.fair) == "THM WARM")
        #expect(MenuBarMetricFormatter.thermalState(.serious) == "THM HOT")
        #expect(MenuBarMetricFormatter.thermalState(.critical) == "THM CRIT")
        #expect(MenuBarMetricFormatter.thermalState(nil) == "THM --")
        #expect(MenuBarMetricFormatter.fixedThermalState("THM OK") == "THM   OK")
        #expect(MenuBarCompactMetricFormatter.thermalStateWidthTemplate == "WARM")
        #expect(MenuBarCompactMetricFormatter.thermalState(.critical) == "CRIT")
        #expect(MenuBarCompactMetricFormatter.fixedThermalState("OK") == "  OK")
    }

    @Test func fixedWidthMenuBarTitleKeepsNetworkCharacterSlotsStable() {
        let lowTraffic = SystemMetrics(
            cpuUsage: 0.12,
            memoryUsedBytes: 8_589_934_592,
            memoryTotalBytes: 17_179_869_184,
            uploadBytesPerSecond: 1_024,
            downloadBytesPerSecond: 1_024,
            sampledAt: Date(timeIntervalSince1970: 0)
        )
        let highTraffic = SystemMetrics(
            cpuUsage: 0.12,
            memoryUsedBytes: 8_589_934_592,
            memoryTotalBytes: 17_179_869_184,
            uploadBytesPerSecond: 123 * 1_024,
            downloadBytesPerSecond: 123 * 1_024,
            sampledAt: Date(timeIntervalSince1970: 0)
        )
        let options = MetricDisplayOptions(
            showsCPU: false,
            showsMemory: false,
            showsNetwork: true
        )

        let lowTitle = MenuBarTitleFormatter.fixedWidthTitle(for: lowTraffic, options: options)
        let highTitle = MenuBarTitleFormatter.fixedWidthTitle(for: highTraffic, options: options)

        #expect(lowTitle == "↑  1.0K ↓  1.0K")
        #expect(highTitle == "↑123.0K ↓123.0K")
        #expect(lowTitle.count == highTitle.count)
        #expect(lowTitle.count == MenuBarTitleFormatter.fixedWidthTemplate(for: options).count)
    }

    @Test func fixedWidthMenuBarTitleKeepsFallbackAndEnabledCombinationsStable() {
        let metrics = SystemMetrics(
            cpuUsage: 0.12,
            memoryUsedBytes: 8_589_934_592,
            memoryTotalBytes: 17_179_869_184,
            uploadBytesPerSecond: 120_000,
            downloadBytesPerSecond: 2_100_000,
            thermalState: .serious,
            sampledAt: Date(timeIntervalSince1970: 0)
        )

        let allEnabled = MetricDisplayOptions(showsCPU: true, showsMemory: true, showsNetwork: true)
        let memoryOnly = MetricDisplayOptions(showsCPU: false, showsMemory: true, showsNetwork: false)
        let thermalOnly = MetricDisplayOptions(
            showsCPU: false,
            showsMemory: false,
            showsNetwork: false,
            showsThermalState: true
        )
        let allDisabled = MetricDisplayOptions(showsCPU: false, showsMemory: false, showsNetwork: false)

        #expect(MenuBarTitleFormatter.fixedWidthTitle(for: metrics, options: allEnabled).count == MenuBarTitleFormatter.fixedWidthTemplate(for: allEnabled).count)
        #expect(MenuBarTitleFormatter.fixedWidthTitle(for: metrics, options: memoryOnly).count == MenuBarTitleFormatter.fixedWidthTemplate(for: memoryOnly).count)
        #expect(MenuBarTitleFormatter.fixedWidthTitle(for: metrics, options: thermalOnly) == "THM  HOT")
        #expect(MenuBarTitleFormatter.fixedWidthTitle(for: metrics, options: thermalOnly).count == MenuBarTitleFormatter.fixedWidthTemplate(for: thermalOnly).count)
        #expect(MenuBarTitleFormatter.fixedWidthTitle(for: metrics, options: allDisabled) == "PulseBar")
        #expect(MenuBarTitleFormatter.fixedWidthTemplate(for: allDisabled) == "PulseBar")
    }

    @Test func fixedWidthMenuBarTitleKeepsThermalStateCharacterSlotsStable() {
        let coolMetrics = SystemMetrics(
            cpuUsage: 0.12,
            memoryUsedBytes: 8_589_934_592,
            memoryTotalBytes: 17_179_869_184,
            uploadBytesPerSecond: 1_024,
            downloadBytesPerSecond: 1_024,
            thermalState: .nominal,
            sampledAt: Date(timeIntervalSince1970: 0)
        )
        let warmMetrics = SystemMetrics(
            cpuUsage: 0.12,
            memoryUsedBytes: 8_589_934_592,
            memoryTotalBytes: 17_179_869_184,
            uploadBytesPerSecond: 123 * 1_024,
            downloadBytesPerSecond: 123 * 1_024,
            thermalState: .fair,
            sampledAt: Date(timeIntervalSince1970: 0)
        )
        let options = MetricDisplayOptions(
            showsCPU: false,
            showsMemory: false,
            showsNetwork: false,
            showsThermalState: true
        )

        let coolTitle = MenuBarTitleFormatter.fixedWidthTitle(for: coolMetrics, options: options)
        let warmTitle = MenuBarTitleFormatter.fixedWidthTitle(for: warmMetrics, options: options)

        #expect(coolTitle == "THM   OK")
        #expect(warmTitle == "THM WARM")
        #expect(coolTitle.count == warmTitle.count)
        #expect(coolTitle.count == MenuBarTitleFormatter.fixedWidthTemplate(for: options).count)
    }

    @Test func menuBarDisplayModesFormatTitles() {
        let metrics = SystemMetrics(
            cpuUsage: 0.12,
            memoryUsedBytes: 8_589_934_592,
            memoryTotalBytes: 17_179_869_184,
            uploadBytesPerSecond: 120_000,
            downloadBytesPerSecond: 2_100_000,
            sampledAt: Date(timeIntervalSince1970: 0)
        )
        let options = MetricDisplayOptions(
            showsCPU: true,
            showsMemory: true,
            showsNetwork: true
        )

        #expect(MenuBarDisplayMode.allCases.map(\.title) == [
            "Standard",
            "Compact",
            "Network Only",
        ])

        let compact = MenuBarDisplayConfiguration(options: options, mode: .compact)
        #expect(MenuBarTitleFormatter.fixedWidthTitle(
            for: metrics,
            configuration: compact
        ) == " 12%    8.0G  ↑117.2K ↓  2.0M")
        #expect(MenuBarTitleFormatter.fixedWidthTitle(
            for: metrics,
            configuration: compact
        ).count == MenuBarTitleFormatter.fixedWidthTemplate(for: compact).count)

        let networkOnly = MenuBarDisplayConfiguration(options: options, mode: .networkOnly)
        #expect(MenuBarTitleFormatter.fixedWidthTitle(
            for: metrics,
            configuration: networkOnly
        ) == "↑117.2K ↓  2.0M")
        #expect(MenuBarTitleFormatter.fixedWidthTitle(
            for: metrics,
            configuration: networkOnly
        ).count == MenuBarTitleFormatter.fixedWidthTemplate(for: networkOnly).count)
    }

    @Test func menuBarTitleFormatterKeepsFallbackForStringConsumers() {
        let metrics = SystemMetrics(
            cpuUsage: 0.12,
            memoryUsedBytes: 8_589_934_592,
            memoryTotalBytes: 17_179_869_184,
            uploadBytesPerSecond: 120_000,
            downloadBytesPerSecond: 2_100_000,
            thermalState: .nominal,
            sampledAt: Date(timeIntervalSince1970: 0)
        )

        #expect(MenuBarTitleFormatter.title(
            for: metrics,
            options: MetricDisplayOptions(
                showsCPU: true,
                showsMemory: true,
                showsNetwork: true,
                showsThermalState: true
            )
        ) == "CPU 12%  MEM 8.0G  ↑117.2K ↓2.0M  THM OK")

        #expect(MenuBarTitleFormatter.title(
            for: metrics,
            options: MetricDisplayOptions(showsCPU: false, showsMemory: true, showsNetwork: false)
        ) == "MEM 8.0G")

        #expect(MenuBarTitleFormatter.title(
            for: metrics,
            options: MetricDisplayOptions(
                showsCPU: false,
                showsMemory: false,
                showsNetwork: false,
                showsThermalState: true
            )
        ) == "THM OK")

        #expect(MenuBarTitleFormatter.title(
            for: metrics,
            options: MetricDisplayOptions(showsCPU: false, showsMemory: false, showsNetwork: false)
        ) == "PulseBar")
    }

    @Test func metricDisplayOptionsReportsVisibleState() {
        #expect(MetricDisplayOptions(showsCPU: true, showsMemory: false, showsNetwork: false).hasVisibleMetrics)
        #expect(MetricDisplayOptions(showsCPU: false, showsMemory: true, showsNetwork: false).hasVisibleMetrics)
        #expect(MetricDisplayOptions(showsCPU: false, showsMemory: false, showsNetwork: true).hasVisibleMetrics)
        #expect(MetricDisplayOptions(
            showsCPU: false,
            showsMemory: false,
            showsNetwork: false,
            showsThermalState: true
        ).hasVisibleMetrics)
        #expect(!MetricDisplayOptions(showsCPU: false, showsMemory: false, showsNetwork: false).hasVisibleMetrics)
    }

}

private var utcCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}

private func testDate(year: Int, month: Int, day: Int, hour: Int) -> Date {
    DateComponents(
        calendar: utcCalendar,
        timeZone: TimeZone(secondsFromGMT: 0),
        year: year,
        month: month,
        day: day,
        hour: hour
    ).date!
}

private enum LaunchAtLoginTestError: Error, Equatable {
    case operationFailed
}

private final class FakeDailyNetworkUsageSnapshotStore: DailyNetworkUsageSnapshotStoring {
    var snapshot: DailyNetworkUsageSnapshot?

    init(snapshot: DailyNetworkUsageSnapshot? = nil) {
        self.snapshot = snapshot
    }

    func loadSnapshot() -> DailyNetworkUsageSnapshot? {
        snapshot
    }

    func saveSnapshot(_ snapshot: DailyNetworkUsageSnapshot) {
        self.snapshot = snapshot
    }
}

private final class FakeAppLoginItemManager: AppLoginItemManaging {
    var status: LaunchAtLoginStatus
    var registerCallCount = 0
    var unregisterCallCount = 0
    var registerError: Error?
    var unregisterError: Error?

    init(status: LaunchAtLoginStatus) {
        self.status = status
    }

    func register() throws {
        registerCallCount += 1

        if let registerError {
            throw registerError
        }

        status = .enabled
    }

    func unregister() throws {
        unregisterCallCount += 1

        if let unregisterError {
            throw unregisterError
        }

        status = .notRegistered
    }
}
