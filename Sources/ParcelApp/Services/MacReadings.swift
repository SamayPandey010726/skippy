import Darwin
import Foundation

/// Two successive samples give CPU utilisation and transfer rates without polling while the arrow is closed.
struct MacReadings {
  var cpu: String
  var memory: String
  var availableDisk: String
  var network: String

  struct Sample {
    let time = ProcessInfo.processInfo.systemUptime
    var idle: UInt32 = 0
    var ticks: UInt64 = 0
    var incoming: UInt64 = 0
    var outgoing: UInt64 = 0
    var activeMemory: UInt64 = 0

    init() {
      let host = mach_host_self()
      defer { mach_port_deallocate(mach_task_self_, host) }
      var cpu = host_cpu_load_info()
      var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: cpu) / MemoryLayout<integer_t>.size)
      _ = withUnsafeMutablePointer(to: &cpu) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
          host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
        }
      }
      idle = cpu.cpu_ticks.2
      ticks = UInt64(cpu.cpu_ticks.0) + UInt64(cpu.cpu_ticks.1) + UInt64(idle) + UInt64(cpu.cpu_ticks.3)
      var vm = vm_statistics64()
      count = mach_msg_type_number_t(MemoryLayout.size(ofValue: vm) / MemoryLayout<integer_t>.size)
      let ok = withUnsafeMutablePointer(to: &vm) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
          host_statistics64(host, HOST_VM_INFO64, $0, &count)
        }
      }
      if ok == KERN_SUCCESS {
        activeMemory = (UInt64(vm.active_count) + UInt64(vm.wire_count) + UInt64(vm.compressor_page_count)) * UInt64(vm_kernel_page_size)
      }
      var list: UnsafeMutablePointer<ifaddrs>?
      guard getifaddrs(&list) == 0, let first = list else { return }
      defer { freeifaddrs(first) }
      var cursor: UnsafeMutablePointer<ifaddrs>? = first
      while let node = cursor {
        let a = node.pointee
        cursor = a.ifa_next
        guard a.ifa_addr?.pointee.sa_family == UInt8(AF_LINK), a.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
          let counters = a.ifa_data?.assumingMemoryBound(to: if_data.self).pointee else { continue }
        incoming += UInt64(counters.ifi_ibytes); outgoing += UInt64(counters.ifi_obytes)
      }
    }
  }

  init(_ sample: Sample, previous: Sample?) {
    func bytes(_ n: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(clamping: n), countStyle: .file) }
    memory = sample.activeMemory > 0 ? bytes(sample.activeMemory) : "Unavailable"
    let space = try? FileManager.default.homeDirectoryForCurrentUser.resourceValues(forKeys: [.volumeAvailableCapacityKey])
    availableDisk = space?.volumeAvailableCapacity.map { bytes(UInt64(max(0, $0))) } ?? "Unavailable"
    cpu = "Sampling…"; network = "Sampling…"
    guard let old = previous, sample.ticks > old.ticks, sample.time > old.time else { return }
    let busy = 1 - Double(sample.idle &- old.idle) / Double(sample.ticks - old.ticks)
    cpu = String(format: "%.0f%%", min(1, max(0, busy)) * 100)
    guard sample.incoming >= old.incoming, sample.outgoing >= old.outgoing else { return }
    let dt = sample.time - old.time
    network = "↓ " + bytes(UInt64(Double(sample.incoming - old.incoming) / dt)) + "/s  ↑ " + bytes(UInt64(Double(sample.outgoing - old.outgoing) / dt)) + "/s"
  }
}
