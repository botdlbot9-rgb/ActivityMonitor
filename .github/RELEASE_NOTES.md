Activity Monitor 1.10.0 adds an Apple Neural Engine (ANE) view and expands process diagnostics with ANE context.

### Neural Engine monitoring

- Added an ANE view with driver-reported device and core counts, visible direct-path process connections, and an estimated whole-Mac power reading from the native macOS Energy Model.
- Added the percentage of each recent interval that the ANE controller spent in its `Running` state. This is controller state, not neural-compute utilization or inference duration.
- Added whole-Mac fabric read and write bandwidth-tier **events per second**. These PMP monitor events respond to ANE work but are not transferred bytes or measured GB/s.
- Added an ANE page to process diagnostics. It charts visible direct-path connections for the selected process and labels system power, controller state, and fabric events separately as whole-Mac context. Connections alone do not establish active inference.
- Exported the read-only `ANETelemetry` Swift library for apps that want the optional native OS counters and full per-tier event histograms without administrator privileges.

ANE counter availability depends on the Mac and macOS version. Some native channels are undocumented, and unavailable readings appear as such. Activity Monitor does not infer per-process ANE watts, utilization, or inference time from system counters or driver connections. [Measurement details and M3 Pro validation](https://github.com/wieslawsoltes/ActivityMonitor/blob/v1.10.0/docs/ANE_VALIDATION.md).

### Install

Use **Check for Updates…** in Activity Monitor 1.9.1, or download the universal DMG or ZIP for Apple silicon and Intel on macOS 14 or later. `SHA256SUMS` verifies the downloads; the update feed and archive are signed with Ed25519.

[Changes since 1.9.1](https://github.com/wieslawsoltes/ActivityMonitor/compare/v1.9.1...v1.10.0)
