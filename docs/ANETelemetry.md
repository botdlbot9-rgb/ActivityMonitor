# ANETelemetry Swift library

The package exports `ANETelemetry` as a reusable macOS 14+ library. It samples
the Neural Engine with read-only native OS APIs and **does not require
administrator privileges**. `ANETelemetrySampler` combines optional IOKit
registry observations with system-wide native IOReport counters:

| Field | Source | Meaning |
| --- | --- | --- |
| `engineCount`, `coreCount` | `H1xANELoadBalancer`, `H11ANEIn` registry properties | Driver-reported hardware descriptors |
| `connections[pid]` | Direct-path ANE user-client registry entries | Open clients visible for that PID, not active inference |
| `estimatedPowerWatts` | Energy Model `ANE` cumulative millijoules | Estimated whole-Mac ANE power rate |
| `controllerRunningPercent` | `ANE / IOP State / status` | Fraction of latest interval in firmware/controller `Running` state |
| `bandwidth.fabricRead`, `.fabricWrite`, `.dcsRead`, `.dcsWrite` | `PMP` ANE0 bandwidth-tier histograms | New monitor events by labeled GB/s tier, plus events per second; **not measured bytes/s** |

```swift
import ANETelemetry
import Foundation

let sampler = ANETelemetrySampler()
_ = sampler.read() // Establish cumulative-counter baselines.
Thread.sleep(forTimeInterval: 1)
let sample = sampler.read()
print(sample.controllerRunningPercent as Any)
print(sample.bandwidth.fabricRead?.eventsByTierGBps as Any)
```

Unknown data remains optional. A measured zero rate is returned only when a
readable bandwidth histogram shows no new events across a valid interval.
Channels are discovered at runtime and loaded dynamically. The user-space
IOReport symbols and channel names are undocumented Apple APIs; they can change
or disappear across chips and macOS versions. The library does not call ANE
driver user-client methods, request private entitlements, use a tracing CLI, or
infer per-process watts, inference latency, or compute utilization from these
system counters. It cannot obtain `AMC Stats` ANE read/write byte counters on
machines where subscription is denied.

See [live validation](ANE_VALIDATION.md) for the M3 Pro observations and limits.
