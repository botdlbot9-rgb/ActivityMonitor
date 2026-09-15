import Foundation

/// Read-only, unprivileged ANE telemetry from native macOS APIs. System-wide
/// counters and visible direct-path PID connections have distinct meanings.
public final class ANETelemetrySampler {
  private let hardware = ANEHardwareReader()
  private let energy = ANEEnergyReader()
  private let controller = ANEControllerReader()
  private let bandwidth = ANEBandwidthReader()

  public init() {}

  /// Call serially from one sampling queue. Consecutive calls establish baselines
  /// and return optional interval rates. No missing value is replaced with zero,
  /// except measured zero PMP events in a valid histogram interval.
  public func read() -> ANEHardwareSnapshot {
    var snapshot = hardware.read()
    snapshot.estimatedPowerWatts = energy.read()
    snapshot.controllerRunningPercent = controller.read()
    snapshot.bandwidth = bandwidth.read()
    return snapshot
  }
}
