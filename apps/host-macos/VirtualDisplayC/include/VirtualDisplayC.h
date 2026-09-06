#include <stdint.h>

/// POC-only wrapper around the undocumented CoreGraphics virtual-display API.
/// Returns 0 when the API is absent or creation fails.
uint32_t DisplayOSCreateVirtualDisplay(const char *name, uint32_t width, uint32_t height, uint32_t refreshRate);
void DisplayOSDestroyVirtualDisplay(void);
