// Throwaway feasibility probe: which GPU and drive readings can a process
// read, with and without the App Sandbox? Prints one fact per line.
#import <Foundation/Foundation.h>
#import <CoreFoundation/CFPlugInCOM.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/IOBSD.h>
#import <IOKit/IOCFPlugIn.h>
#import <IOKit/storage/nvme/NVMeSMARTLibExternal.h>
#import <Metal/Metal.h>
#import <sys/mount.h>
#import <pwd.h>
#import <dlfcn.h>

static void out(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void out(NSString *format, ...) {
  va_list args;
  va_start(args, format);
  NSString *text = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);
  printf("%s\n", text.UTF8String);
  fflush(stdout);
}

static NSString *classOf(io_object_t object) {
  io_name_t name = {0};
  IOObjectGetClass(object, name);
  return @(name);
}

static id prop(io_registry_entry_t entry, NSString *key) {
  return CFBridgingRelease(
    IORegistryEntryCreateCFProperty(entry, (__bridge CFStringRef)key, kCFAllocatorDefault, 0));
}

// MARK: GPU

static void probeGPU(void) {
  out(@"## GPU (IORegistry)");
  io_iterator_t iterator = 0;
  kern_return_t kr = IOServiceGetMatchingServices(
    kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator);
  out(@"gpu.match kr=0x%x", kr);
  if (kr != KERN_SUCCESS) return;

  io_object_t service;
  int accelerators = 0;
  while ((service = IOIteratorNext(iterator))) {
    accelerators++;
    NSDictionary *stats = prop(service, @"PerformanceStatistics");
    out(@"gpu.accelerator class=%@ model=%@ cores=%@ perfStats=%@", classOf(service),
      prop(service, @"model"), prop(service, @"gpu-core-count"), stats ? @"READABLE" : @"nil");
    for (NSString *key in @[
           @"Device Utilization %", @"Renderer Utilization %", @"Tiler Utilization %",
           @"In use system memory", @"Alloc system memory",
         ]) {
      out(@"gpu.stat %@ = %@", key, stats[key]);
    }

    io_iterator_t children = 0;
    kr = IORegistryEntryGetChildIterator(service, kIOServicePlane, &children);
    out(@"gpu.children kr=0x%x", kr);
    int clients = 0, withCreator = 0, withUsage = 0, printed = 0;
    io_object_t child;
    while (kr == KERN_SUCCESS && (child = IOIteratorNext(children))) {
      clients++;
      NSString *creator = prop(child, @"IOUserClientCreator");
      id usage = prop(child, @"AppUsage");
      if (creator) withCreator++;
      if (usage) withUsage++;
      if (usage && printed < 3) {
        printed++;
        NSString *text = [[usage description] stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
        out(@"gpu.client sample creator=[%@] usage=%@", creator, text);
      }
      IOObjectRelease(child);
    }
    if (children) IOObjectRelease(children);
    out(@"gpu.clients total=%d withCreator=%d withAppUsage=%d", clients, withCreator, withUsage);
    IOObjectRelease(service);
  }
  IOObjectRelease(iterator);
  out(@"gpu.accelerators count=%d", accelerators);

  out(@"## GPU (Metal, public API)");
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  if (device) {
    out(@"metal name=%@ unifiedMemory=%d recommendedMaxWorkingSetSize=%llu", device.name,
      device.hasUnifiedMemory, (unsigned long long)device.recommendedMaxWorkingSetSize);
  } else {
    out(@"metal device=nil");
  }
}

// MARK: Volumes

static NSString *bsdNameForPath(NSString *path, NSString **fsType) {
  struct statfs info;
  if (statfs(path.fileSystemRepresentation, &info) != 0) {
    out(@"statfs %@ FAILED errno=%d", path, errno);
    return nil;
  }
  if (fsType) *fsType = @(info.f_fstypename);
  NSString *from = @(info.f_mntfromname);
  return [from hasPrefix:@"/dev/"] ? [from substringFromIndex:5] : from;
}

static void mapToDriver(NSString *bsdName) {
  io_service_t media = IOServiceGetMatchingService(
    kIOMainPortDefault, IOBSDNameMatching(kIOMainPortDefault, 0, bsdName.UTF8String));
  if (!media) {
    out(@"map %@ media=NOT-FOUND", bsdName);
    return;
  }
  IOOptionBits up = kIORegistryIterateRecursively | kIORegistryIterateParents;
  NSDictionary *protocol = CFBridgingRelease(IORegistryEntrySearchCFProperty(
    media, kIOServicePlane, CFSTR("Protocol Characteristics"), kCFAllocatorDefault, up));
  NSDictionary *device = CFBridgingRelease(IORegistryEntrySearchCFProperty(
    media, kIOServicePlane, CFSTR("Device Characteristics"), kCFAllocatorDefault, up));

  NSMutableArray<NSString *> *chain = [NSMutableArray array];
  NSDictionary *stats = nil;
  NSString *driverDisk = nil;
  BOOL found = NO;
  io_registry_entry_t current = media;
  for (int depth = 0; depth < 40 && current; depth++) {
    [chain addObject:classOf(current)];
    if (IOObjectConformsTo(current, "IOBlockStorageDriver")) {
      found = YES;
      stats = prop(current, @"Statistics");
      driverDisk = CFBridgingRelease(IORegistryEntrySearchCFProperty(
        current, kIOServicePlane, CFSTR("BSD Name"), kCFAllocatorDefault,
        kIORegistryIterateRecursively));
      IOObjectRelease(current);
      current = 0;
      break;
    }
    io_registry_entry_t parent = 0;
    kern_return_t kr = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent);
    IOObjectRelease(current);
    current = (kr == KERN_SUCCESS) ? parent : 0;
  }
  if (current) IOObjectRelease(current);
  out(@"map %@ driverFound=%d physicalDisk=%@ stats=%@ interconnect=%@ location=%@ medium=%@ product=%@ hops=%lu",
    bsdName, found, driverDisk, stats ? @"READABLE" : @"nil",
    protocol[@"Physical Interconnect"], protocol[@"Physical Interconnect Location"],
    device[@"Medium Type"], device[@"Product Name"], (unsigned long)chain.count);
}

static void probeVolumes(void) {
  out(@"## Volumes (public Foundation API)");
  NSArray<NSURLResourceKey> *keys = @[
    NSURLVolumeNameKey, NSURLVolumeTotalCapacityKey, NSURLVolumeAvailableCapacityKey,
    NSURLVolumeAvailableCapacityForImportantUsageKey, NSURLVolumeIsInternalKey,
    NSURLVolumeIsRemovableKey, NSURLVolumeIsEjectableKey, NSURLVolumeIsLocalKey,
    NSURLVolumeLocalizedFormatDescriptionKey, NSURLVolumeIsRootFileSystemKey,
  ];
  NSArray<NSURL *> *volumes = [[NSFileManager defaultManager]
    mountedVolumeURLsIncludingResourceValuesForKeys:keys
                                            options:NSVolumeEnumerationSkipHiddenVolumes];
  out(@"volumes count=%lu", (unsigned long)volumes.count);
  for (NSURL *url in volumes) {
    NSError *error = nil;
    NSDictionary *v = [url resourceValuesForKeys:keys error:&error];
    NSString *fsType = nil;
    NSString *bsd = bsdNameForPath(url.path, &fsType);
    out(@"volume path=%@ name=%@ total=%@ avail=%@ availImportant=%@ internal=%@ removable=%@ ejectable=%@ local=%@ format=%@ root=%@ bsd=%@ fs=%@ error=%@",
      url.path, v[NSURLVolumeNameKey], v[NSURLVolumeTotalCapacityKey],
      v[NSURLVolumeAvailableCapacityKey], v[NSURLVolumeAvailableCapacityForImportantUsageKey],
      v[NSURLVolumeIsInternalKey], v[NSURLVolumeIsRemovableKey], v[NSURLVolumeIsEjectableKey],
      v[NSURLVolumeIsLocalKey], v[NSURLVolumeLocalizedFormatDescriptionKey],
      v[NSURLVolumeIsRootFileSystemKey], bsd, fsType, error.localizedDescription);
    if (bsd) mapToDriver(bsd);
  }
}

// MARK: Disk activity

static NSDictionary<NSString *, NSArray<NSNumber *> *> *blockStats(int *drivers, int *unreadable) {
  NSMutableDictionary *result = [NSMutableDictionary dictionary];
  io_iterator_t iterator = 0;
  kern_return_t kr = IOServiceGetMatchingServices(
    kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator);
  if (kr != KERN_SUCCESS) {
    out(@"blockstats.match FAILED kr=0x%x", kr);
    return result;
  }
  io_object_t service;
  while ((service = IOIteratorNext(iterator))) {
    (*drivers)++;
    NSDictionary *stats = prop(service, @"Statistics");
    NSString *bsd = CFBridgingRelease(IORegistryEntrySearchCFProperty(
      service, kIOServicePlane, CFSTR("BSD Name"), kCFAllocatorDefault,
      kIORegistryIterateRecursively));
    if (stats && bsd) {
      result[bsd] = @[stats[@"Bytes (Read)"] ?: @0, stats[@"Bytes (Write)"] ?: @0];
    } else {
      (*unreadable)++;
    }
    IOObjectRelease(service);
  }
  IOObjectRelease(iterator);
  return result;
}

static void probeDiskActivity(void) {
  out(@"## Disk activity (IORegistry counters, two samples)");
  int drivers = 0, unreadable = 0;
  NSDictionary *first = blockStats(&drivers, &unreadable);
  out(@"blockstats drivers=%d unreadable=%d", drivers, unreadable);

  // Make sure the internal disk has something to count.
  NSString *scratch = [NSTemporaryDirectory() stringByAppendingPathComponent:@"probe-write.bin"];
  NSData *payload = [NSMutableData dataWithLength:48 * 1024 * 1024];
  NSError *writeError = nil;
  BOOL wrote = [payload writeToFile:scratch options:NSDataWritingAtomic error:&writeError];
  int fd = open(scratch.fileSystemRepresentation, O_RDONLY);
  if (fd >= 0) { fcntl(fd, F_FULLFSYNC); close(fd); }
  out(@"blockstats scratchWrite ok=%d dir=%@ error=%@", wrote, NSTemporaryDirectory(),
    writeError.localizedDescription);
  [NSThread sleepForTimeInterval:1.0];

  int ignored = 0, ignored2 = 0;
  NSDictionary *second = blockStats(&ignored, &ignored2);
  for (NSString *disk in [second.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
    NSArray<NSNumber *> *a = first[disk], *b = second[disk];
    if (!a) continue;
    long long readDelta = b[0].longLongValue - a[0].longLongValue;
    long long writeDelta = b[1].longLongValue - a[1].longLongValue;
    if (readDelta || writeDelta || [disk isEqualToString:@"disk0"]) {
      out(@"blockstats %@ totalRead=%@ totalWrite=%@ deltaRead=%lld deltaWrite=%lld", disk, b[0],
        b[1], readDelta, writeDelta);
    }
  }
  [[NSFileManager defaultManager] removeItemAtPath:scratch error:NULL];
}

// MARK: SMART (public IOKit header, needs a user client)

static void probeSMART(void) {
  out(@"## NVMe SMART (IOKit/storage/nvme/NVMeSMARTLibExternal.h)");
  NSDictionary *match = @{ @kIOPropertyMatchKey : @{ @kIOPropertyNVMeSMARTCapableKey : @YES } };
  io_iterator_t iterator = 0;
  kern_return_t kr = IOServiceGetMatchingServices(
    kIOMainPortDefault, (__bridge_retained CFDictionaryRef)match, &iterator);
  out(@"smart.match kr=0x%x", kr);
  if (kr != KERN_SUCCESS) return;
  io_object_t service;
  int count = 0;
  while ((service = IOIteratorNext(iterator))) {
    count++;
    IOCFPlugInInterface **plugin = NULL;
    SInt32 score = 0;
    kr = IOCreatePlugInInterfaceForService(
      service, kIONVMeSMARTUserClientTypeID, kIOCFPlugInInterfaceID, &plugin, &score);
    out(@"smart.device class=%@ createPlugIn kr=0x%x plugin=%@", classOf(service), kr,
      plugin ? @"ok" : @"NULL");
    if (kr == KERN_SUCCESS && plugin) {
      IONVMeSMARTInterface **smart = NULL;
      HRESULT hr = (*plugin)->QueryInterface(
        plugin, CFUUIDGetUUIDBytes(kIONVMeSMARTInterfaceID), (LPVOID *)&smart);
      out(@"smart.queryInterface hr=0x%x", (unsigned)hr);
      if (hr == S_OK && smart) {
        NVMeSMARTData data;
        memset(&data, 0, sizeof(data));
        IOReturn result = (*smart)->SMARTReadData(smart, &data);
        out(@"smart.read result=0x%x criticalWarning=%u temperatureK=%u temperatureC=%d availableSpare=%u spareThreshold=%u percentageUsed=%u",
          result, data.CRITICAL_WARNING, data.TEMPERATURE, (int)data.TEMPERATURE - 273,
          data.AVAILABLE_SPARE, data.AVAILABLE_SPARE_THRESHOLD, data.PERCENTAGE_USED);
        (*smart)->Release(smart);
      }
      IODestroyPlugInInterface(plugin);
    }
    IOObjectRelease(service);
  }
  IOObjectRelease(iterator);
  out(@"smart.capableDevices count=%d", count);
}

// MARK: Files

static void probeFiles(void) {
  out(@"## File access");
  struct passwd *pw = getpwuid(getuid());
  NSString *realHome = pw ? @(pw->pw_dir) : nil;
  out(@"files NSHomeDirectory=%@ realHome=%@", NSHomeDirectory(), realHome);
  for (NSString *path in @[ realHome ?: @"/nonexistent",
         [realHome stringByAppendingPathComponent:@"Movies"] ?: @"/nonexistent", @"/Applications" ]) {
    NSError *error = nil;
    NSArray *items = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:&error];
    out(@"files list %@ => %@", path,
      items ? [NSString stringWithFormat:@"%lu items", (unsigned long)items.count]
            : [NSString stringWithFormat:@"DENIED (%@)", error.localizedDescription]);
  }
}

// MARK: Private frameworks (measured for completeness, not a recommendation)

typedef CFDictionaryRef (*CopyChannelsFn)(CFStringRef, CFStringRef, uint64_t, uint64_t, uint64_t);
typedef void *(*CreateSubscriptionFn)(void *, CFMutableDictionaryRef, CFMutableDictionaryRef *, uint64_t, CFTypeRef);
typedef CFDictionaryRef (*CreateSamplesFn)(void *, CFMutableDictionaryRef, CFTypeRef);
typedef CFDictionaryRef (*CreateDeltaFn)(CFDictionaryRef, CFDictionaryRef, CFTypeRef);
typedef CFStringRef (*ChannelStringFn)(CFDictionaryRef);
typedef int64_t (*SimpleIntFn)(CFDictionaryRef, int32_t);

static void probeIOReport(void) {
  out(@"## PRIVATE: IOReport (GPU energy)");
  void *lib = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW);
  if (!lib) { out(@"ioreport dlopen FAILED"); return; }
  CopyChannelsFn copyChannels = dlsym(lib, "IOReportCopyChannelsInGroup");
  CreateSubscriptionFn subscribe = dlsym(lib, "IOReportCreateSubscription");
  CreateSamplesFn sample = dlsym(lib, "IOReportCreateSamples");
  CreateDeltaFn delta = dlsym(lib, "IOReportCreateSamplesDelta");
  ChannelStringFn channelName = dlsym(lib, "IOReportChannelGetChannelName");
  ChannelStringFn unitLabel = dlsym(lib, "IOReportChannelGetUnitLabel");
  SimpleIntFn simpleInt = dlsym(lib, "IOReportSimpleGetIntegerValue");
  if (!copyChannels || !subscribe || !sample || !delta || !channelName || !simpleInt) {
    out(@"ioreport symbols MISSING");
    return;
  }
  CFDictionaryRef channels = copyChannels(CFSTR("Energy Model"), NULL, 0, 0, 0);
  if (!channels) { out(@"ioreport channels=NULL"); return; }
  CFMutableDictionaryRef wanted = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, channels);
  CFMutableDictionaryRef subscribed = NULL;
  void *subscription = subscribe(NULL, wanted, &subscribed, 0, NULL);
  if (!subscription) { out(@"ioreport subscription=NULL (DENIED)"); return; }
  CFDictionaryRef first = sample(subscription, subscribed, NULL);
  [NSThread sleepForTimeInterval:1.0];
  CFDictionaryRef second = sample(subscription, subscribed, NULL);
  if (!first || !second) { out(@"ioreport samples=NULL (DENIED)"); return; }
  NSDictionary *diff = CFBridgingRelease(delta(first, second, NULL));
  NSArray *list = diff[@"IOReportChannels"];
  out(@"ioreport energyChannels=%lu", (unsigned long)list.count);
  for (NSDictionary *channel in list) {
    NSString *name = (__bridge NSString *)channelName((__bridge CFDictionaryRef)channel);
    if ([name containsString:@"GPU"]) {
      NSString *unit = unitLabel ? (__bridge NSString *)unitLabel((__bridge CFDictionaryRef)channel) : nil;
      out(@"ioreport %@ = %lld %@ over 1s", name,
        (long long)simpleInt((__bridge CFDictionaryRef)channel, 0), unit);
    }
  }
}

typedef void *(*HIDCreateFn)(CFAllocatorRef);
typedef int (*HIDSetMatchingFn)(void *, CFDictionaryRef);
typedef CFArrayRef (*HIDCopyServicesFn)(void *);
typedef CFTypeRef (*HIDCopyPropertyFn)(void *, CFStringRef);
typedef void *(*HIDCopyEventFn)(void *, int64_t, int32_t, int64_t);
typedef double (*HIDFloatFn)(void *, int32_t);

static void probeHIDSensors(void) {
  out(@"## PRIVATE: IOHIDEventSystem temperature sensors");
  HIDCreateFn create = dlsym(RTLD_DEFAULT, "IOHIDEventSystemClientCreate");
  HIDSetMatchingFn setMatching = dlsym(RTLD_DEFAULT, "IOHIDEventSystemClientSetMatching");
  HIDCopyServicesFn copyServices = dlsym(RTLD_DEFAULT, "IOHIDEventSystemClientCopyServices");
  HIDCopyPropertyFn copyProperty = dlsym(RTLD_DEFAULT, "IOHIDServiceClientCopyProperty");
  HIDCopyEventFn copyEvent = dlsym(RTLD_DEFAULT, "IOHIDServiceClientCopyEvent");
  HIDFloatFn floatValue = dlsym(RTLD_DEFAULT, "IOHIDEventGetFloatValue");
  if (!create || !setMatching || !copyServices || !copyProperty || !copyEvent || !floatValue) {
    out(@"hid symbols MISSING");
    return;
  }
  void *client = create(kCFAllocatorDefault);
  if (!client) { out(@"hid client=NULL (DENIED)"); return; }
  NSDictionary *match = @{ @"PrimaryUsagePage" : @(0xff00), @"PrimaryUsage" : @(5) };
  setMatching(client, (__bridge CFDictionaryRef)match);
  NSArray *services = CFBridgingRelease(copyServices(client));
  out(@"hid temperatureServices=%lu", (unsigned long)services.count);
  int withValue = 0, printed = 0;
  for (id service in services) {
    NSString *name = CFBridgingRelease(copyProperty((__bridge void *)service, CFSTR("Product")));
    void *event = copyEvent((__bridge void *)service, 15, 0, 0);
    if (!event) continue;
    double celsius = floatValue(event, 15 << 16);
    CFRelease(event);
    withValue++;
    if (printed < 40 && ([name containsString:@"GPU"] || [name containsString:@"NAND"]
          || [name containsString:@"SSD"] || [name hasPrefix:@"PMU tdie"])) {
      printed++;
      out(@"hid sensor %@ = %.1f C", name, celsius);
    }
  }
  out(@"hid sensorsWithValue=%d", withValue);
}

int main(void) {
  @autoreleasepool {
    out(@"# probe pid=%d sandboxContainerEnv=%s", getpid(),
      getenv("APP_SANDBOX_CONTAINER_ID") ?: "(unset)");
    probeGPU();
    probeVolumes();
    probeDiskActivity();
    probeSMART();
    probeFiles();
    probeIOReport();
    probeHIDSensors();
    out(@"# done");
  }
  return 0;
}
