import CoreFoundation
import Darwin
import Foundation

/// The OS Energy Model reports cumulative estimated ANE energy in millijoules.
/// This is system-wide power, not ANE utilization or per-process inference time.
enum ANEEnergyRate {
  static func watts(previous: Int64, current: Int64, seconds: TimeInterval) -> Double? {
    guard previous >= 0, current >= previous, seconds.isFinite,
      seconds >= 0.1, seconds <= 60 else { return nil }
    let value = Double(current - previous) / (1000 * seconds)
    return value.isFinite && value >= 0 ? value : nil
  }
}

/// Optional native OS counter. libIOReport is an undocumented macOS library;
/// discover the exact channel and unit at runtime and omit the value if they
/// change or the current user cannot subscribe.
final class ANEEnergyReader {
  private typealias CopyGroup = @convention(c)(
    UnsafeRawPointer?, UnsafeRawPointer?, UInt64,
    UnsafeMutablePointer<UnsafeRawPointer?>?) -> UnsafeRawPointer?
  private typealias Subscribe = @convention(c)(
    UnsafeRawPointer?, UnsafeRawPointer?, UnsafeMutablePointer<UnsafeRawPointer?>?, UInt64,
    UnsafeMutablePointer<UnsafeRawPointer?>?) -> UnsafeRawPointer?
  private typealias CreateSamples = @convention(c)(
    UnsafeRawPointer?, UnsafeRawPointer?, UnsafeMutablePointer<UnsafeRawPointer?>?)
    -> UnsafeRawPointer?
  private typealias GetValue = @convention(c)(UnsafeRawPointer?, UnsafeMutablePointer<UInt64>?)
    -> Int64
  private typealias GetLabel = @convention(c)(UnsafeRawPointer?) -> UnsafeRawPointer?

  private var library: UnsafeMutableRawPointer?
  private var subscription: UnsafeRawPointer?
  private var channels: UnsafeRawPointer?
  private var createSamples: CreateSamples?
  private var getValue: GetValue?
  private var getLabel: GetLabel?
  private var attempted = false
  private var previous: (value: Int64, time: Date)?

  deinit {
    if let subscription { Unmanaged<CFTypeRef>.fromOpaque(subscription).release() }
    if let channels { Unmanaged<CFDictionary>.fromOpaque(channels).release() }
    if let library { dlclose(library) }
  }

  func read() -> Double? {
    if !attempted {
      attempted = true
      configure()
    }
    guard let subscription, let channels, let createSamples, let getValue, let getLabel else {
      return nil
    }
    var error: UnsafeRawPointer?
    guard let raw = createSamples(subscription, channels, &error) else {
      releaseError(error)
      previous = nil
      return nil
    }
    releaseError(error)
    let sample = Unmanaged<CFDictionary>.fromOpaque(raw).takeRetainedValue() as NSDictionary
    guard let channel = (sample["IOReportChannels"] as? [NSDictionary])?.first else {
      previous = nil
      return nil
    }
    let channelPointer = Unmanaged.passUnretained(channel as CFDictionary).toOpaque()
    guard let label = getLabel(channelPointer),
      Unmanaged<CFString>.fromOpaque(label).takeUnretainedValue() as String == "mJ"
    else {
      previous = nil
      return nil
    }
    var unit: UInt64 = 0
    let current = getValue(channelPointer, &unit)
    let time = Date()
    guard current >= 0 else {
      previous = nil
      return nil
    }
    let power = previous.flatMap {
      ANEEnergyRate.watts(previous: $0.value, current: current,
        seconds: time.timeIntervalSince($0.time))
    }
    previous = (current, time)
    return power
  }

  private func configure() {
    guard let library = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW) else { return }
    self.library = library
    guard
      let copyGroup: CopyGroup = symbol("IOReportCopyChannelsInGroup", library: library),
      let subscribe: Subscribe = symbol("IOReportCreateSubscription", library: library),
      let createSamples: CreateSamples = symbol("IOReportCreateSamples", library: library),
      let getValue: GetValue = symbol("IOReportSimpleGetIntegerValue", library: library),
      let getLabel: GetLabel = symbol("IOReportChannelGetUnitLabel", library: library)
    else { return }
    let group: CFString = "Energy Model" as CFString
    var error: UnsafeRawPointer?
    guard let raw = copyGroup(Unmanaged.passUnretained(group).toOpaque(), nil, 0, &error)
    else {
      releaseError(error)
      return
    }
    releaseError(error)
    let available = Unmanaged<CFDictionary>.fromOpaque(raw).takeRetainedValue() as NSDictionary
    guard let entries = available["IOReportChannels"] as? [NSDictionary],
      let channel = entries.first(where: { entry in
        guard entry["IOReportGroupName"] as? String == "Energy Model",
          let legend = entry["LegendChannel"] as? [Any], legend.count >= 3
        else { return false }
        return legend[2] as? String == "ANE"
      }), let options = available["QueryOpts"]
    else { return }
    let selected = NSMutableDictionary(dictionary: [
      "QueryOpts": options, "IOReportChannels": [channel],
    ])
    var subscribedChannels: UnsafeRawPointer?
    error = nil
    guard let subscription = subscribe(nil,
      Unmanaged.passUnretained(selected as CFDictionary).toOpaque(),
      &subscribedChannels, 0, &error)
    else {
      releaseError(error)
      if let subscribedChannels {
        Unmanaged<CFDictionary>.fromOpaque(subscribedChannels).release()
      }
      return
    }
    releaseError(error)
    guard let subscribedChannels else {
      Unmanaged<CFTypeRef>.fromOpaque(subscription).release()
      return
    }
    self.subscription = subscription
    self.channels = subscribedChannels
    self.createSamples = createSamples
    self.getValue = getValue
    self.getLabel = getLabel
  }

  private func symbol<T>(_ name: String, library: UnsafeMutableRawPointer) -> T? {
    dlsym(library, name).map { unsafeBitCast($0, to: T.self) }
  }
  private func releaseError(_ error: UnsafeRawPointer?) {
    if let error { Unmanaged<CFError>.fromOpaque(error).release() }
  }
}
