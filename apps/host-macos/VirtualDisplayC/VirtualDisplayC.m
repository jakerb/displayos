#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/message.h>
#import "VirtualDisplayC.h"

// These Objective-C classes are intentionally resolved at runtime. They are
// undocumented macOS implementation details and must never be used in a
// shipping App Store build.
static id activeDisplay;

static void setInteger(id object, SEL selector, NSUInteger value) {
    ((void (*)(id, SEL, NSUInteger))objc_msgSend)(object, selector, value);
}
static void setObject(id object, SEL selector, id value) {
    ((void (*)(id, SEL, id))objc_msgSend)(object, selector, value);
}

uint32_t DisplayOSCreateVirtualDisplay(const char *name, uint32_t width, uint32_t height, uint32_t refreshRate) {
    @try {
        Class descriptorClass = NSClassFromString(@"CGVirtualDisplayDescriptor");
        Class displayClass = NSClassFromString(@"CGVirtualDisplay");
        Class modeClass = NSClassFromString(@"CGVirtualDisplayMode");
        Class settingsClass = NSClassFromString(@"CGVirtualDisplaySettings");
        if (!descriptorClass || !displayClass || !modeClass || !settingsClass) return 0;

        id descriptor = [descriptorClass new];
        setObject(descriptor, NSSelectorFromString(@"setName:"), [NSString stringWithUTF8String:name]);
        setInteger(descriptor, NSSelectorFromString(@"setMaxPixelsWide:"), width);
        setInteger(descriptor, NSSelectorFromString(@"setMaxPixelsHigh:"), height);
        ((void (*)(id, SEL, CGSize))objc_msgSend)(descriptor, NSSelectorFromString(@"setSizeInMillimeters:"), CGSizeMake(597, 336));
        setInteger(descriptor, NSSelectorFromString(@"setVendorID:"), 0xD150);
        setInteger(descriptor, NSSelectorFromString(@"setProductID:"), 0x0001);
        setInteger(descriptor, NSSelectorFromString(@"setSerialNum:"), 0x00010001);

        id mode = ((id (*)(id, SEL, NSUInteger, NSUInteger, double))objc_msgSend)([modeClass alloc], NSSelectorFromString(@"initWithWidth:height:refreshRate:"), width, height, (double)refreshRate);
        id settings = [settingsClass new];
        setObject(settings, NSSelectorFromString(@"setModes:"), @[mode]);
        setInteger(settings, NSSelectorFromString(@"setHiDPI:"), 0);

        activeDisplay = ((id (*)(id, SEL, id))objc_msgSend)([displayClass alloc], NSSelectorFromString(@"initWithDescriptor:"), descriptor);
        BOOL applied = ((BOOL (*)(id, SEL, id))objc_msgSend)(activeDisplay, NSSelectorFromString(@"applySettings:"), settings);
        if (!applied) { activeDisplay = nil; return 0; }
        return ((uint32_t (*)(id, SEL))objc_msgSend)(activeDisplay, NSSelectorFromString(@"displayID"));
    } @catch (NSException *exception) {
        activeDisplay = nil;
        return 0;
    }
}

void DisplayOSDestroyVirtualDisplay(void) {
    if (activeDisplay && [activeDisplay respondsToSelector:NSSelectorFromString(@"invalidate")]) {
        ((void (*)(id, SEL))objc_msgSend)(activeDisplay, NSSelectorFromString(@"invalidate"));
    }
    activeDisplay = nil;
}
