//
//  SystemMetricsMonitor.swift
//  PulseBar
//
//  Created by lingjhf on 2026/6/12.
//

import Combine
import Darwin
import Foundation

@MainActor
final class SystemMetricsMonitor: ObservableObject {
    @Published private(set) var metrics: SystemMetrics = .empty

    private let sampler: LiveSystemMetricsSampler
    private let interval: TimeInterval
    private var timer: Timer?
    private var thermalStateObserver: NSObjectProtocol?

    init(sampler: LiveSystemMetricsSampler? = nil, interval: TimeInterval = 1) {
        self.sampler = sampler ?? LiveSystemMetricsSampler()
        self.interval = interval
        refresh()
        start()
        startThermalStateObserver()
    }

    deinit {
        timer?.invalidate()
        if let thermalStateObserver {
            NotificationCenter.default.removeObserver(thermalStateObserver)
        }
    }

    func refresh() {
        metrics = sampler.sample()
    }

    private func start() {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let monitor = self else {
                return
            }

            Task { @MainActor [weak monitor] in
                monitor?.refresh()
            }
        }
        timer?.tolerance = interval * 0.1
    }

    private func startThermalStateObserver() {
        thermalStateObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }
}

final class LiveSystemMetricsSampler {
    private var previousCPUTicks: CPUTicks?
    private var previousNetworkCounters: NetworkCounters?
    private let dailyNetworkUsageTracker: DailyNetworkUsageTracker

    init(dailyNetworkUsageTracker: DailyNetworkUsageTracker = DailyNetworkUsageTracker()) {
        self.dailyNetworkUsageTracker = dailyNetworkUsageTracker
    }

    func sample() -> SystemMetrics {
        let sampledAt = Date()

        let cpuTicks = readCPUTicks()
        let cpuUsage = cpuTicks.flatMap {
            SystemMetricsCalculator.cpuUsage(current: $0, previous: previousCPUTicks)
        }
        if let cpuTicks {
            previousCPUTicks = cpuTicks
        }

        let memory = readMemory()

        let networkCounters = readNetworkCounters(sampledAt: sampledAt)
        let networkRates = networkCounters.flatMap {
            SystemMetricsCalculator.networkRates(current: $0, previous: previousNetworkCounters)
        }
        let dailyNetworkUsage = networkCounters.map {
            dailyNetworkUsageTracker.update(current: $0)
        }
        if let networkCounters {
            previousNetworkCounters = networkCounters
        }

        return SystemMetrics(
            cpuUsage: cpuUsage,
            memoryUsedBytes: memory?.usedBytes,
            memoryTotalBytes: memory?.totalBytes,
            uploadBytesPerSecond: networkRates?.uploadBytesPerSecond,
            downloadBytesPerSecond: networkRates?.downloadBytesPerSecond,
            todayUploadBytes: dailyNetworkUsage?.uploadBytes,
            todayDownloadBytes: dailyNetworkUsage?.downloadBytes,
            thermalState: readThermalState(),
            sampledAt: sampledAt
        )
    }

    private func readThermalState() -> SystemThermalState {
        SystemThermalState(ProcessInfo.processInfo.thermalState)
    }

    private func readCPUTicks() -> CPUTicks? {
        var processorInfo: processor_info_array_t?
        var processorInfoCount: mach_msg_type_number_t = 0
        var processorCount: natural_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &processorInfo,
            &processorInfoCount
        )

        guard result == KERN_SUCCESS, let processorInfo else {
            return nil
        }

        defer {
            let byteCount = vm_size_t(Int(processorInfoCount) * MemoryLayout<integer_t>.stride)
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: processorInfo)),
                byteCount
            )
        }

        var ticks = CPUTicks(user: 0, system: 0, idle: 0, nice: 0)
        let stateCount = Int(CPU_STATE_MAX)

        for cpuIndex in 0..<Int(processorCount) {
            let base = cpuIndex * stateCount
            ticks.user += UInt64(processorInfo[base + Int(CPU_STATE_USER)])
            ticks.system += UInt64(processorInfo[base + Int(CPU_STATE_SYSTEM)])
            ticks.idle += UInt64(processorInfo[base + Int(CPU_STATE_IDLE)])
            ticks.nice += UInt64(processorInfo[base + Int(CPU_STATE_NICE)])
        }

        return ticks
    }

    private func readMemory() -> (usedBytes: UInt64, totalBytes: UInt64)? {
        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else {
            return nil
        }

        var stats = vm_statistics64()
        var statsCount = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(statsCount)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &statsCount)
            }
        }

        guard result == KERN_SUCCESS else {
            return nil
        }

        let totalBytes = ProcessInfo.processInfo.physicalMemory
        let memoryStats = MemoryPageStats(
            internalPages: UInt64(stats.internal_page_count),
            wiredPages: UInt64(stats.wire_count),
            compressorPages: UInt64(stats.compressor_page_count)
        )

        guard let usedBytes = SystemMetricsCalculator.memoryUsedBytes(
            stats: memoryStats,
            pageSize: UInt64(pageSize),
            totalBytes: totalBytes
        ) else {
            return nil
        }

        return (usedBytes: usedBytes, totalBytes: totalBytes)
    }

    private func readNetworkCounters(sampledAt: Date) -> NetworkCounters? {
        var interfaceAddresses: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&interfaceAddresses) == 0, let firstAddress = interfaceAddresses else {
            return nil
        }

        defer {
            freeifaddrs(interfaceAddresses)
        }

        var receivedBytes: UInt64 = 0
        var sentBytes: UInt64 = 0

        for pointer in sequence(first: firstAddress, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            let flags = Int32(interface.ifa_flags)

            guard
                flags & IFF_UP != 0,
                flags & IFF_LOOPBACK == 0,
                let address = interface.ifa_addr,
                address.pointee.sa_family == UInt8(AF_LINK),
                let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self)
            else {
                continue
            }

            receivedBytes += UInt64(data.pointee.ifi_ibytes)
            sentBytes += UInt64(data.pointee.ifi_obytes)
        }

        return NetworkCounters(
            receivedBytes: receivedBytes,
            sentBytes: sentBytes,
            sampledAt: sampledAt
        )
    }
}
