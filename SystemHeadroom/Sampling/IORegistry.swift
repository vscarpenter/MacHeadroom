import Foundation
import IOKit

/// The IORegistry calls the GPU and drive samplers share. Reading a
/// registry property is allowed under the App Sandbox; opening a user
/// client is not (SANDBOX_NOTES.md, November 13, 2026). Nothing here
/// opens one.
enum IORegistry {
  static func forEachService(className: String, _ body: (io_service_t) -> Void) {
    forEachService(matching: IOServiceMatching(className), body)
  }

  /// IOServiceGetMatchingServices consumes the matching dictionary.
  static func forEachService(matching: CFDictionary?, _ body: (io_service_t) -> Void) {
    guard let matching else { return }
    var iterator: io_iterator_t = 0
    guard
      IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS
    else { return }
    defer { IOObjectRelease(iterator) }
    drain(iterator, body)
  }

  static func forEachChild(
    of entry: io_registry_entry_t, _ body: (io_registry_entry_t) -> Void
  ) {
    var iterator: io_iterator_t = 0
    guard
      IORegistryEntryGetChildIterator(entry, kIOServicePlane, &iterator) == KERN_SUCCESS
    else { return }
    defer { IOObjectRelease(iterator) }
    drain(iterator, body)
  }

  static func property(_ key: String, of entry: io_registry_entry_t) -> Any? {
    IORegistryEntryCreateCFProperty(entry, key as CFString, nil, 0)?.takeRetainedValue()
  }

  /// The nearest value for `key` on the entry or any ancestor.
  static func searchParents(_ key: String, from entry: io_registry_entry_t) -> Any? {
    IORegistryEntrySearchCFProperty(
      entry, kIOServicePlane, key as CFString, nil,
      IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents))
  }

  /// The nearest value for `key` on the entry or any descendant.
  static func searchChildren(_ key: String, from entry: io_registry_entry_t) -> Any? {
    IORegistryEntrySearchCFProperty(
      entry, kIOServicePlane, key as CFString, nil,
      IOOptionBits(kIORegistryIterateRecursively))
  }

  /// Walks up the service plane from `entry`, itself included, and
  /// calls `body` with the first object that conforms to `className`.
  static func withFirstAncestor<Result>(
    of entry: io_registry_entry_t,
    conformingTo className: String,
    _ body: (io_registry_entry_t) -> Result
  ) -> Result? {
    var current = entry
    var ownsCurrent = false
    defer { if ownsCurrent { IOObjectRelease(current) } }

    // A volume sits about nine hops below its driver; the cap only
    // guards against a malformed plane.
    for _ in 0..<64 {
      if IOObjectConformsTo(current, className) != 0 {
        return body(current)
      }
      var parent: io_registry_entry_t = 0
      guard
        IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS,
        parent != 0
      else { return nil }
      if ownsCurrent { IOObjectRelease(current) }
      current = parent
      ownsCurrent = true
    }
    return nil
  }

  private static func drain(_ iterator: io_iterator_t, _ body: (io_object_t) -> Void) {
    while true {
      let object = IOIteratorNext(iterator)
      guard object != 0 else { return }
      body(object)
      IOObjectRelease(object)
    }
  }
}
