import CoreFoundation
import Darwin
import Foundation

/// Fraction of an interval that the ANE controller reports its Running state.
/// Running means firmware/controller state, not neural-compute utilization.
enum ANEControllerRate {
  static func runningPercent(
    previous: [String: Int64], current: [String: Int64], seconds: TimeInterval
  ) -> Double? {
    guard seconds.isFinite, (0.1...60).contains(seconds),
      Set(previous.keys) == Set(current.keys), previous["Running"] != nil,
      previous["Off"] != nil else { return nil }
    var total = 0.0
    var running = 0.0
    for (name, value) in current where name != "unused" {
      guard let earlier = previous[name], earlier >= 0, value >= earlier else { return nil }
      let delta = Double(value - earlier)
      total += delta
      if name == "Running" { running = delta }
    }
    guard total > 0, running.isFinite, total.isFinite,
      running >= 0, running <= total else { return nil }
    return running / total * 100
  }
}

/// Optional native OS state channel. libIOReport and the channel names are
/// undocumented; an unavailable or changed channel produces no reading.
final class ANEControllerReader {
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

  private var library: UnsafeMutableRawPointer?
  private var subscription: UnsafeRawPointer?
  private var channels: UnsafeRawPointer?
  private var createSamples: CreateSamples?
  private var stateCount: GetCount?
  private var stateName: GetName?
  private var stateResidency: GetResidency?
  private var attempted = false
  private var previous: (states: [String: Int64], time: Date)?

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
    guard let subscription, let channels, let createSamples,
      let stateCount, let stateName, let stateResidency else { return nil }
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
    let pointer = Unmanaged.passUnretained(channel as CFDictionary).toOpaque()
    let count = stateCount(pointer)
    guard (2...64).contains(count) else {
      previous = nil
      return nil
    }
    var states: [String: Int64] = [:]
    for index in 0..<count {
      guard let rawName = stateName(pointer, index) else {
        previous = nil
        return nil
      }
      let name = (Unmanaged<CFString>.fromOpaque(rawName).takeUnretainedValue() as String)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard !name.isEmpty, states[name] == nil else {
        previous = nil
        return nil
      }
      states[name] = stateResidency(pointer, index)
    }
    let now = Date()
    let percent = previous.flatMap {
      ANEControllerRate.runningPercent(
        previous: $0.states, current: states,
        seconds: now.timeIntervalSince($0.time))
    }
    previous = (states, now)
    return percent
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
      let stateResidency: GetResidency = symbol("IOReportStateGetResidency", library: library)
    else { return }
    let group = "ANE" as CFString
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
        let pointer = Unmanaged.passUnretained(entry as CFDictionary).toOpaque()
        return Self.string(getGroup(pointer)) == "ANE"
          && Self.string(getSubgroup(pointer)) == "IOP State"
          && Self.string(getName(pointer)) == "status"
      }), let options = available["QueryOpts"] else { return }
    let selected = NSMutableDictionary(dictionary: [
      "QueryOpts": options, "IOReportChannels": [channel],
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
    self.stateCount = stateCount
    self.stateName = stateName
    self.stateResidency = stateResidency
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
