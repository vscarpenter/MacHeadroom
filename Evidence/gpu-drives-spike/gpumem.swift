// Throwaway experiment: which IOAccelerator memory counter moves when a
// process allocates Metal buffers, and when it touches them?
import Foundation
import IOKit
import Metal

func stats() -> (inUse: UInt64, alloc: UInt64) {
  var iterator: io_iterator_t = 0
  IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator)
  defer { IOObjectRelease(iterator) }
  let service = IOIteratorNext(iterator)
  defer { IOObjectRelease(service) }
  let dict = IORegistryEntryCreateCFProperty(
    service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
    .takeRetainedValue() as? [String: Any]
  let inUse = (dict?["In use system memory"] as? NSNumber)?.uint64Value ?? 0
  let alloc = (dict?["Alloc system memory"] as? NSNumber)?.uint64Value ?? 0
  return (inUse, alloc)
}

func report(_ label: String, base: (inUse: UInt64, alloc: UInt64)) {
  let now = stats()
  let mb = { (a: UInt64, b: UInt64) in (Int64(a) - Int64(b)) / 1_048_576 }
  print("\(label): inUse \(now.inUse / 1_048_576) MB (delta \(mb(now.inUse, base.inUse))), "
    + "alloc \(now.alloc / 1_048_576) MB (delta \(mb(now.alloc, base.alloc)))")
}

guard let device = MTLCreateSystemDefaultDevice() else { fatalError("no Metal device") }
let base = stats()
report("baseline", base: base)

let chunk = 256 * 1024 * 1024
var buffers: [MTLBuffer] = []
for _ in 0..<8 {
  if let buffer = device.makeBuffer(length: chunk, options: .storageModeShared) {
    buffers.append(buffer)
  }
}
Thread.sleep(forTimeInterval: 1)
report("after allocating 8 x 256 MB shared buffers (untouched)", base: base)

for buffer in buffers {
  memset(buffer.contents(), 0x5A, chunk)
}
Thread.sleep(forTimeInterval: 1)
report("after writing every page", base: base)

// Use them on the GPU: blit each buffer onto itself.
if let queue = device.makeCommandQueue(), let command = queue.makeCommandBuffer(),
  let blit = command.makeBlitCommandEncoder()
{
  for buffer in buffers {
    blit.copy(from: buffer, sourceOffset: 0, to: buffer, destinationOffset: chunk / 2, size: chunk / 2)
  }
  blit.endEncoding()
  command.commit()
  command.waitUntilCompleted()
}
Thread.sleep(forTimeInterval: 1)
report("after a GPU blit over every buffer", base: base)

var privateBuffers: [MTLBuffer] = []
for _ in 0..<4 {
  if let buffer = device.makeBuffer(length: chunk, options: .storageModePrivate) {
    privateBuffers.append(buffer)
  }
}
Thread.sleep(forTimeInterval: 1)
report("after 4 x 256 MB private buffers", base: base)

buffers.removeAll()
privateBuffers.removeAll()
Thread.sleep(forTimeInterval: 2)
report("after releasing everything", base: base)
