//
//  MetricFormatting.swift
//  PulseBar
//
//  Created by lingjhf on 2026/6/12.
//

import Foundation

enum MenuBarTitleFormatter {
    static func title(for metrics: SystemMetrics, options: MetricDisplayOptions) -> String {
        var parts: [String] = []

        if options.showsCPU {
            parts.append("CPU \(MetricValueFormatter.percentage(metrics.cpuUsage))")
        }

        if options.showsMemory {
            parts.append("MEM \(MetricValueFormatter.compactMemory(metrics.memoryUsedBytes))")
        }

        if options.showsNetwork {
            let upload = MetricValueFormatter.compactByteRate(metrics.uploadBytesPerSecond)
            let download = MetricValueFormatter.compactByteRate(metrics.downloadBytesPerSecond)
            parts.append("↑\(upload) ↓\(download)")
        }

        return parts.isEmpty ? "PulseBar" : parts.joined(separator: "  ")
    }

    static func fixedWidthTitle(
        for metrics: SystemMetrics,
        configuration: MenuBarDisplayConfiguration
    ) -> String {
        switch configuration.mode {
        case .standard:
            fixedWidthTitle(for: metrics, options: configuration.options)
        case .compact:
            compactFixedWidthTitle(for: metrics, options: configuration.options)
        case .networkOnly:
            networkOnlyFixedWidthTitle(for: metrics)
        }
    }

    static func fixedWidthTemplate(for configuration: MenuBarDisplayConfiguration) -> String {
        switch configuration.mode {
        case .standard:
            fixedWidthTemplate(for: configuration.options)
        case .compact:
            compactFixedWidthTemplate(for: configuration.options)
        case .networkOnly:
            networkOnlyFixedWidthTemplate()
        }
    }

    static func fixedWidthTitle(for metrics: SystemMetrics, options: MetricDisplayOptions) -> String {
        fixedWidthTitle(
            cpu: MenuBarMetricFormatter.cpu(metrics.cpuUsage),
            memory: MenuBarMetricFormatter.memory(metrics.memoryUsedBytes),
            upload: MenuBarMetricFormatter.upload(metrics.uploadBytesPerSecond),
            download: MenuBarMetricFormatter.download(metrics.downloadBytesPerSecond),
            options: options
        )
    }

    static func fixedWidthTemplate(for options: MetricDisplayOptions) -> String {
        fixedWidthTitle(
            cpu: MenuBarMetricFormatter.cpuWidthTemplate,
            memory: MenuBarMetricFormatter.memoryWidthTemplate,
            upload: MenuBarMetricFormatter.uploadWidthTemplate,
            download: MenuBarMetricFormatter.downloadWidthTemplate,
            options: options
        )
    }

    private static func fixedWidthTitle(
        cpu: String,
        memory: String,
        upload: String,
        download: String,
        options: MetricDisplayOptions
    ) -> String {
        var parts: [String] = []

        if options.showsCPU {
            parts.append(MenuBarMetricFormatter.fixedCPU(cpu))
        }

        if options.showsMemory {
            parts.append(MenuBarMetricFormatter.fixedMemory(memory))
        }

        if options.showsNetwork {
            parts.append([
                MenuBarMetricFormatter.fixedUpload(upload),
                MenuBarMetricFormatter.fixedDownload(download),
            ].joined(separator: " "))
        }

        return parts.isEmpty ? "PulseBar" : parts.joined(separator: "  ")
    }

    private static func compactFixedWidthTitle(for metrics: SystemMetrics, options: MetricDisplayOptions) -> String {
        compactFixedWidthTitle(
            cpu: MenuBarCompactMetricFormatter.cpu(metrics.cpuUsage),
            memory: MenuBarCompactMetricFormatter.memory(metrics.memoryUsedBytes),
            upload: MenuBarMetricFormatter.upload(metrics.uploadBytesPerSecond),
            download: MenuBarMetricFormatter.download(metrics.downloadBytesPerSecond),
            options: options
        )
    }

    private static func compactFixedWidthTemplate(for options: MetricDisplayOptions) -> String {
        compactFixedWidthTitle(
            cpu: MenuBarCompactMetricFormatter.cpuWidthTemplate,
            memory: MenuBarCompactMetricFormatter.memoryWidthTemplate,
            upload: MenuBarMetricFormatter.uploadWidthTemplate,
            download: MenuBarMetricFormatter.downloadWidthTemplate,
            options: options
        )
    }

    private static func compactFixedWidthTitle(
        cpu: String,
        memory: String,
        upload: String,
        download: String,
        options: MetricDisplayOptions
    ) -> String {
        var parts: [String] = []

        if options.showsCPU {
            parts.append(MenuBarCompactMetricFormatter.fixedCPU(cpu))
        }

        if options.showsMemory {
            parts.append(MenuBarCompactMetricFormatter.fixedMemory(memory))
        }

        if options.showsNetwork {
            parts.append([
                MenuBarMetricFormatter.fixedUpload(upload),
                MenuBarMetricFormatter.fixedDownload(download),
            ].joined(separator: " "))
        }

        return parts.isEmpty ? "PulseBar" : parts.joined(separator: "  ")
    }

    private static func networkOnlyFixedWidthTitle(for metrics: SystemMetrics) -> String {
        [
            MenuBarMetricFormatter.fixedUpload(
                MenuBarMetricFormatter.upload(metrics.uploadBytesPerSecond)
            ),
            MenuBarMetricFormatter.fixedDownload(
                MenuBarMetricFormatter.download(metrics.downloadBytesPerSecond)
            ),
        ].joined(separator: " ")
    }

    private static func networkOnlyFixedWidthTemplate() -> String {
        [
            MenuBarMetricFormatter.fixedUpload(MenuBarMetricFormatter.uploadWidthTemplate),
            MenuBarMetricFormatter.fixedDownload(MenuBarMetricFormatter.downloadWidthTemplate),
        ].joined(separator: " ")
    }
}

enum MenuBarMetricFormatter {
    static let cpuWidthTemplate = "CPU 100%"
    static let memoryWidthTemplate = "MEM 999.9G"
    static let uploadWidthTemplate = "↑999.9G"
    static let downloadWidthTemplate = "↓999.9G"

    static func cpu(_ value: Double?) -> String {
        "CPU \(MetricValueFormatter.percentage(value))"
    }

    static func memory(_ bytes: UInt64?) -> String {
        "MEM \(MetricValueFormatter.compactMemory(bytes))"
    }

    static func upload(_ bytesPerSecond: Double?) -> String {
        "↑\(MetricValueFormatter.compactByteRate(bytesPerSecond))"
    }

    static func download(_ bytesPerSecond: Double?) -> String {
        "↓\(MetricValueFormatter.compactByteRate(bytesPerSecond))"
    }

    static func fixedCPU(_ text: String) -> String {
        leftPadSuffix(in: text, prefix: "CPU ", template: cpuWidthTemplate)
    }

    static func fixedMemory(_ text: String) -> String {
        leftPadSuffix(in: text, prefix: "MEM ", template: memoryWidthTemplate)
    }

    static func fixedUpload(_ text: String) -> String {
        leftPadSuffix(in: text, prefix: "↑", template: uploadWidthTemplate)
    }

    static func fixedDownload(_ text: String) -> String {
        leftPadSuffix(in: text, prefix: "↓", template: downloadWidthTemplate)
    }

    private static func leftPadSuffix(in text: String, prefix: String, template: String) -> String {
        guard text.hasPrefix(prefix) else {
            return text
        }

        let suffix = String(text.dropFirst(prefix.count))
        let suffixWidth = template.count - prefix.count
        let padding = max(0, suffixWidth - suffix.count)

        return "\(prefix)\(String(repeating: " ", count: padding))\(suffix)"
    }
}

enum MenuBarCompactMetricFormatter {
    static let cpuWidthTemplate = "100%"
    static let memoryWidthTemplate = "999.9G"

    static func cpu(_ value: Double?) -> String {
        MetricValueFormatter.percentage(value)
    }

    static func memory(_ bytes: UInt64?) -> String {
        MetricValueFormatter.compactMemory(bytes)
    }

    static func fixedCPU(_ text: String) -> String {
        leftPad(text, template: cpuWidthTemplate)
    }

    static func fixedMemory(_ text: String) -> String {
        leftPad(text, template: memoryWidthTemplate)
    }

    private static func leftPad(_ text: String, template: String) -> String {
        let padding = max(0, template.count - text.count)
        return "\(String(repeating: " ", count: padding))\(text)"
    }
}

enum MetricValueFormatter {
    static func percentage(_ value: Double?) -> String {
        guard let value else {
            return "--"
        }

        let percent = max(0, min(value, 1)) * 100
        return "\(Int(percent.rounded()))%"
    }

    static func compactMemory(_ bytes: UInt64?) -> String {
        guard let bytes else {
            return "--"
        }

        return scaledBytes(Double(bytes), units: ["B", "K", "M", "G", "T"])
    }

    static func memorySummary(usedBytes: UInt64?, totalBytes: UInt64?) -> String {
        guard let usedBytes, let totalBytes else {
            return "--"
        }

        return "\(byteAmount(usedBytes)) / \(byteAmount(totalBytes))"
    }

    static func byteRate(_ bytesPerSecond: Double?) -> String {
        guard let bytesPerSecond else {
            return "--"
        }

        return "\(scaledBytes(bytesPerSecond, units: ["B", "KB", "MB", "GB", "TB"]))/s"
    }

    static func byteAmount(_ bytes: UInt64?) -> String {
        guard let bytes else {
            return "--"
        }

        return scaledBytes(Double(bytes), units: ["B", "KB", "MB", "GB", "TB"])
    }

    static func compactByteRate(_ bytesPerSecond: Double?) -> String {
        guard let bytesPerSecond else {
            return "--"
        }

        return scaledBytes(bytesPerSecond, units: ["B", "K", "M", "G", "T"])
    }

    private static func byteAmount(_ bytes: UInt64) -> String {
        scaledBytes(Double(bytes), units: ["B", "KB", "MB", "GB", "TB"])
    }

    private static func scaledBytes(_ bytes: Double, units: [String]) -> String {
        var value = max(0, bytes)
        var unitIndex = 0

        while value >= 1024, unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        if unitIndex == 0 {
            return "\(Int(value.rounded()))\(units[unitIndex])"
        }

        return String(format: "%.1f%@", value, units[unitIndex])
    }
}
