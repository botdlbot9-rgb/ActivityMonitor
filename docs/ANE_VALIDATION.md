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

Process diagnostics has an ANE page with a history of the selected PID's visible
direct-path connections. A second chart on that page shows the live system-wide
power estimate as context, expressly covering all processes. The process
overview and compact inspector report the selected PID's connection count; the
inspector labels system watts separately. No process watts or inference duration
is inferred from the presence, absence, or timing of a connection.

## Additional native OS channel survey

On the same M3 Pro and macOS 26.6, `IOReportCopyAllChannels` enumerated 9,804
channels. `PMP` / `Fast-Die CE` / `ANE0` exposed state buckets named `0%` through
`100%`, and `PMP` / `DCS Floor` / `ANE0` exposed `F1` through `F5`. Both channels
subscribed as a normal user, but every state counter stayed zero during idle
samples and a sustained 2,000-request Vision image-classification workload. The
buckets therefore **cannot support a utilization or frequency reading on this
machine**. `AMC Stats` / `Perf Counters` / `ANE RD` and `ANE WR` were discoverable
but refused subscriptions. ANE-index interrupt counters were accessible but did
not track individual model requests or provide meaningful inference counts.

The `ANE` / `IOP State` / `status` channel did provide cumulative controller-state
residencies. During the sustained Vision workload, `Running` increased while
`Off` stayed flat; the measured interval was about 100% Running state. After the
workload, `Off` increased while `Running` stayed flat; the idle interval was 0%
Running state. The app now computes this percentage from differences between
successive native samples, showing it only when both samples and the full state
total are valid. This measures controller state across the whole Mac, **not ANE
neural-compute utilization**. A Running controller can be waiting or handling
firmware work, and macOS supplies no arbitrary-PID inference duration here.

The `PMP` / `AF BW` and `PMP` / `DCS BW` channels named `ANE0 RD` and `ANE0 WR`
were separately subscribable as a normal user. Each supplied tier labels such
as `1GB/s` through `32GB/s` and cumulative counts with the unit `events`. Across
idle intervals, no new events appeared. During a second sustained 2,000-request
Vision workload, fabric read and DCS read histograms each added roughly 5,290
events in their sampled intervals; separate fabric write and DCS write intervals
also added roughly 5,300 events. This shows ANE-labeled bandwidth-monitor
activity, but the counters do **not** state bytes moved or provide a calibrated
data-transfer rate. The library preserves the tier-event deltas and the app
displays their event rate, leaving actual GB/s unavailable.
