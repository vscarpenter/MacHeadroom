// NVMeSMARTBridge.h: one C function over IOKit's public NVMe SMART
// plug-in interface (IOKit/storage/nvme/NVMeSMARTLibExternal.h). Swift
// does not import the interface's UUID macros, and the COM-style call
// chain is far shorter in C.
//
// Calling this opens a user client. The App Sandbox denies that
// (deny iokit-open-user-client AppleNVMeSMARTUserClient; SANDBOX_NOTES.md,
// November 13, 2026), so only the unsandboxed Direct build calls it.
// DriveHealthCapability is the gate.
#ifndef NVME_SMART_BRIDGE_H
#define NVME_SMART_BRIDGE_H

#include <CoreFoundation/CFPlugInCOM.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/storage/nvme/NVMeSMARTLibExternal.h>
#include <string.h>

typedef struct {
  uint8_t criticalWarning;
  uint16_t temperatureKelvin;
  uint8_t availableSpare;
  uint8_t availableSpareThreshold;
  uint8_t percentageUsed;
} HeadroomNVMeHealth;

// Reads the SMART health page of one NVMe SMART capable service. On any
// failure `health` is left untouched and the IOKit error is returned.
static inline kern_return_t HeadroomReadNVMeHealth(
  io_service_t service, HeadroomNVMeHealth *health
) {
  IOCFPlugInInterface **plugIn = NULL;
  SInt32 score = 0;
  kern_return_t result = IOCreatePlugInInterfaceForService(
    service, kIONVMeSMARTUserClientTypeID, kIOCFPlugInInterfaceID, &plugIn, &score);
  if (result != KERN_SUCCESS) {
    return result;
  }
  if (plugIn == NULL) {
    return kIOReturnError;
  }

  IONVMeSMARTInterface **smart = NULL;
  HRESULT query = (*plugIn)->QueryInterface(
    plugIn, CFUUIDGetUUIDBytes(kIONVMeSMARTInterfaceID), (LPVOID *)&smart);
  if (query != S_OK || smart == NULL) {
    IODestroyPlugInInterface(plugIn);
    return kIOReturnUnsupported;
  }

  NVMeSMARTData data;
  memset(&data, 0, sizeof(data));
  result = (*smart)->SMARTReadData(smart, &data);
  if (result == KERN_SUCCESS) {
    health->criticalWarning = data.CRITICAL_WARNING;
    health->temperatureKelvin = data.TEMPERATURE;
    health->availableSpare = data.AVAILABLE_SPARE;
    health->availableSpareThreshold = data.AVAILABLE_SPARE_THRESHOLD;
    health->percentageUsed = data.PERCENTAGE_USED;
  }

  (*smart)->Release(smart);
  IODestroyPlugInInterface(plugIn);
  return result;
}

#endif
