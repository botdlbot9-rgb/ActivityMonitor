import CoreFoundation
import Darwin
import Foundation

/// Native PMP bandwidth-tier histogram. Counts are monitor events in labeled
/// tiers, not transferred bytes or a calibrated bytes-per-second measurement.
public struct ANEBandwidthHistogram: Equatable {
  public let eventsByTierGBps: [Int: Int64]
  public let totalEvents: Int64
  public let eventsPerSecond: Double
}

public struct ANEBandwidthSnapshot: Equatable {
  public var fabricRead: ANEBandwidthHistogram?
  public var fabricWrite: ANEBandwidthHistogram?
  public var dcsRead: ANEBandwidthHistogram?
  public var dcsWrite: ANEBandwidthHistogram?
  public init() {}
}

enum ANEBandwidthRate {
  static func histogram(
    previous: [Int: Int64], current: [Int: Int64], seconds: TimeInterval
  ) -> ANEBandwidthHistogram? {
    guard seconds.isFinite, (0.1...60).contains(seconds),
      !current.isEmpty, Set(previous.keys) == Set(current.keys) else { return nil }
    var delta: [Int: Int64] = [:]
    var total: Int64 = 0
    for (tier, value) in current {
      guard (1...128).contains(tier), let earlier = previous[tier],
        earlier >= 0, value >= earlier else { return nil }
      let change = value - earlier
      let (next, overflow) = total.addingReportingOverflow(change)
      guard !overflow else { return nil }
      total = next
      delta[tier] = change
    }
    let rate = Double(total) / seconds
    guard rate.isFinite, rate >= 0 else { return nil }
    return ANEBandwidthHistogram(
      eventsByTierGBps: delta, totalEvents: total, eventsPerSecond: rate)
  }
}

/// Dynamically discovers four optional ANE-labeled read/write monitor channels.
/// Each subscription is separate so an unavailable channel cannot hide others.
final class ANEBandwidthReader {
  private typealias CopyGroup = @convention(c)(
    UnsafeRawPointer?, UnsafeRawPointer?, UInt64,
    UnsafeMutablePointer<UnsafeRawPointer?>?) -> UnsafeRawPointer?
  private typealias Subscribe = @convention(c)(
    UnsafeRawPointer?, UnsafeRawPointer?, UnsafeMutablePointer<UnsafeRawPointer?>?, UInt64,
    UnsafeMutablePointer<UnsafeRawPointer?>?) -> UnsafeRawPointer?
  private typealias CreateSamples = @convention(c)(
    UnsafeRawPointer?, UnsafeRawPointer?, UnsafeMutablePointer<UnsafeRawPointer?>?)
    -> UnsafeRawPointer?
  private typealias GetString = @convention(c)(UnsafeRawPointer?) -> UnsafeRawPointer?
  private typealias GetCount = @convention(c)(UnsafeRawPointer?) -> Int32
  private typealias GetName = @convention(c)(UnsafeRawPointer?, Int32) -> UnsafeRawPointer?
  private typealias GetResidency = @convention(c)(UnsafeRawPointer?, Int32) -> Int64

  private final class Channel {
    let subscription: UnsafeRawPointer
    let channels: UnsafeRawPointer
    var previous: (values: [Int: Int64], time: Date)?
    init(subscription: UnsafeRawPointer, channels: UnsafeRawPointer) {
      self.subscription = subscription
      self.channels = channels
    }
    deinit {
      Unmanaged<CFTypeRef>.fromOpaque(subscription).release()
      Unmanaged<CFDictionary>.fromOpaque(channels).release()
    }
  }
  private var library: UnsafeMutableRawPointer?
  private var attempted = false
  private var subscriptions: [String: Channel] = [:]
  private var createSamples: CreateSamples?
  private var stateCount: GetCount?
  private var stateName: GetName?
  private var stateResidency: GetResidency?
  private var unitLabel: GetString?

  deinit {
    subscriptions.removeAll()
    if let library { dlclose(library) }
  }
  func read() -> ANEBandwidthSnapshot {
    if !attempted {
      attempted = true
      configure()
    }
    var result = ANEBandwidthSnapshot()
    result.fabricRead = sample("AF BW/ANE0 RD")
    result.fabricWrite = sample("AF BW/ANE0 WR")
    result.dcsRead = sample("DCS BW/ANE0 RD")
    result.dcsWrite = sample("DCS BW/ANE0 WR")
    return result
  }

  private func sample(_ key: String) -> ANEBandwidthHistogram? {
    guard let channel = subscriptions[key], let createSamples,
      let stateCount, let stateName, let stateResidency, let unitLabel else { return nil }
    var error: UnsafeRawPointer?
    guard let raw = createSamples(channel.subscription, channel.channels, &error) else {
      releaseError(error)
      channel.previous = nil
      return nil
    }
    releaseError(error)
    let sample = Unmanaged<CFDictionary>.fromOpaque(raw).takeRetainedValue() as NSDictionary
    guard let entry = (sample["IOReportChannels"] as? [NSDictionary])?.first else {
      channel.previous = nil
      return nil
    }
    let pointer = Unmanaged.passUnretained(entry as CFDictionary).toOpaque()
    guard Self.string(unitLabel(pointer)) == "events",
      (1...64).contains(stateCount(pointer)) else {
      channel.previous = nil
      return nil
    }
    var values: [Int: Int64] = [:]
    for index in 0..<stateCount(pointer) {
      let label = Self.string(stateName(pointer, index))
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard label.hasSuffix("GB/s"),
        let tier = Int(label.dropLast(4)),
        (1...128).contains(tier), values[tier] == nil else {
        channel.previous = nil
        return nil
      }
      values[tier] = stateResidency(pointer, index)
    }
    let now = Date()
    let histogram = channel.previous.flatMap {
      ANEBandwidthRate.histogram(
        previous: $0.values, current: values,
        seconds: now.timeIntervalSince($0.time))
    }
    channel.previous = (values, now)
    return histogram
  }

  private func configure() {
    guard let library = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW) else { return }
    self.library = library
    guard let copyGroup: CopyGroup = symbol("IOReportCopyChannelsInGroup", library: library),
      let subscribe: Subscribe = symbol("IOReportCreateSubscription", library: library),
      let createSamples: CreateSamples = symbol("IOReportCreateSamples", library: library),
      let getGroup: GetString = symbol("IOReportChannelGetGroup", library: library),
      let getSubgroup: GetString = symbol("IOReportChannelGetSubGroup", library: library),
      let getName: GetString = symbol("IOReportChannelGetChannelName", library: library),
      let stateCount: GetCount = symbol("IOReportStateGetCount", library: library),
      let stateName: GetName = symbol("IOReportStateGetNameForIndex", library: library),
      let stateResidency: GetResidency = symbol("IOReportStateGetResidency", library: library),
      let unitLabel: GetString = symbol("IOReportChannelGetUnitLabel", library: library)
    else { return }
    let group = "PMP" as CFString
    var error: UnsafeRawPointer?
    guard let raw = copyGroup(Unmanaged.passUnretained(group).toOpaque(), nil, 0, &error)
    else {
      releaseError(error)
      return
    }
    releaseError(error)
    let available = Unmanaged<CFDictionary>.fromOpaque(raw).takeRetainedValue() as NSDictionary
    guard let entries = available["IOReportChannels"] as? [NSDictionary],
      let options = available["QueryOpts"] else { return }
    for (subgroup, name) in [
      ("AF BW", "ANE0 RD"), ("AF BW", "ANE0 WR"),
      ("DCS BW", "ANE0 RD"), ("DCS BW", "ANE0 WR"),
    ] {
      guard let entry = entries.first(where: { entry in
        let pointer = Unmanaged.passUnretained(entry as CFDictionary).toOpaque()
        return Self.string(getGroup(pointer)) == "PMP"
          && Self.string(getSubgroup(pointer)) == subgroup
          && Self.string(getName(pointer)) == name
      }) else { continue }
      let selected = NSMutableDictionary(dictionary: [
        "QueryOpts": options, "IOReportChannels": [entry],
      ])
      var subscribedChannels: UnsafeRawPointer?
      error = nil
      guard let subscription = subscribe(nil,
        Unmanaged.passUnretained(selected as CFDictionary).toOpaque(),
        &subscribedChannels, 0, &error) else {
        releaseError(error)
        if let subscribedChannels {
          Unmanaged<CFDictionary>.fromOpaque(subscribedChannels).release()
        }
        continue
      }
      releaseError(error)
      guard let subscribedChannels else {
        Unmanaged<CFTypeRef>.fromOpaque(subscription).release()
        continue
      }
      subscriptions["\(subgroup)/\(name)"] = Channel(
        subscription: subscription, channels: subscribedChannels)
    }
    self.createSamples = createSamples
    self.stateCount = stateCount
    self.stateName = stateName
    self.stateResidency = stateResidency
    self.unitLabel = unitLabel
  }

  private static func string(_ raw: UnsafeRawPointer?) -> String {
    guard let raw else { return "" }
    return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
  }
  private func symbol<T>(_ name: String, library: UnsafeMutableRawPointer) -> T? {
    dlsym(library, name).map { unsafeBitCast($0, to: T.self) }
  }
  private func releaseError(_ error: UnsafeRawPointer?) {
    if let error { Unmanaged<CFError>.fromOpaque(error).release() }
  }
}
