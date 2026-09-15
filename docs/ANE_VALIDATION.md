# ANE validation

September 15, 2026 · Apple M3 Pro · macOS 26.6.

`ioreg` showed `H11ANEIn` with `ANEDevicePropertyNumANECores = 16` and
`H1xANELoadBalancer` with `ANEDevicePropertyNumANEs = 1`. Two
`H1xANELoadBalancerDirectPathClient` descendants exposed `IOUserClientCreator`
PIDs. A separate load-balancer client belonged to `aned`; it was excluded from
the per-process count. The read-only collector reported **one device, 16 cores,
two direct connections, two processes** on the same machine.

Reproduce without administrator rights:

```sh
swiftc Sources/ActivityMonitor/ANECollector.swift scripts/ane-probe.swift \
  -framework IOKit -o /tmp/activity-monitor-ane-probe
/tmp/activity-monitor-ane-probe
```

Connections reflect driver contexts, not currently running inference. Neither
`H11ANEIn` nor the load-balancer properties observed here exposed execution time
or utilization. The native macOS `libIOReport.dylib` Energy Model exposed a
system-wide `ANE` counter with the unit `mJ`. A subscription to this one channel
and samples through `IOReportCreateSamples` succeeded as a normal user. A one-
second idle interval read 0 W; a separate 100-request Vision image-classification
workload produced approximately 1.51 W as the difference in cumulative energy
divided by elapsed time. The first read establishes a baseline and is unavailable.
Counter resets, unreadable samples, missing channels, and unit changes produce
an unavailable value rather than zero.

This is an **estimated system-wide power rate**, not compute utilization,
inference latency, physical power measurement, or per-process attribution. The
user-space IOReport API is undocumented, so channel names and subscription
access may change. It is loaded dynamically and the feature disappears if
unavailable. No CLI or administrator rights are used by the app. Apple’s Core
ML/Neural Engine Instruments remain the supported tool for detailed model
timing and activity. No physical validation on another Apple silicon generation
has been performed; registry class names and energy-channel availability can
differ.
