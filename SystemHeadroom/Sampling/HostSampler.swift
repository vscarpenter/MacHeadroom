import Darwin
import Foundation

struct HostCPUTicks: Sendable, Equatable {
  let user: UInt32
  let system: UInt32
  let idle: UInt32
  let nice: UInt32

  var totalTicks: UInt64 {
    UInt64(user) + UInt64(system) + UInt64(idle) + UInt64(nice)
  }

  var busyTicks: UInt64 {
    UInt64(user) + UInt64(system) + UInt64(nice)
  }
}

struct HostMemorySnapshot: Sendable, Equatable {
  let totalBytes: UInt64
  let usedBytes: UInt64
}

enum HostSampler {
  static func sampleCPUTicks() -> HostCPUTicks? {
    var cpuLoad = host_cpu_load_info_data_t()
    var count = mach_msg_type_number_t(
      MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
    )
    let result = withUnsafeMutablePointer(to: &cpuLoad) { pointer -> kern_return_t in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
        host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, intPointer, &count)
      }
    }
    guard result == KERN_SUCCESS else { return nil }
    return HostCPUTicks(
      user: cpuLoad.cpu_ticks.0,
      system: cpuLoad.cpu_ticks.1,
      idle: cpuLoad.cpu_ticks.2,
      nice: cpuLoad.cpu_ticks.3
    )
  }

  static func sampleMemory() -> HostMemorySnapshot? {
    var stats = vm_statistics64_data_t()
    var count = mach_msg_type_number_t(
      MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
    )
    let result = withUnsafeMutablePointer(to: &stats) { pointer -> kern_return_t in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
        host_statistics64(mach_host_self(), HOST_VM_INFO64, intPointer, &count)
      }
    }
    guard result == KERN_SUCCESS else { return nil }

    var pageSize: vm_size_t = 0
    host_page_size(mach_host_self(), &pageSize)

    var totalBytes: UInt64 = 0
    var size = MemoryLayout<UInt64>.size
    guard sysctlbyname("hw.memsize", &totalBytes, &size, nil, 0) == 0 else { return nil }

    let usedPages =
      UInt64(stats.active_count) + UInt64(stats.wire_count)
      + UInt64(stats.compressor_page_count)
    return HostMemorySnapshot(totalBytes: totalBytes, usedBytes: usedPages * UInt64(pageSize))
  }
}
