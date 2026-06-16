#include <IOKit/hid/IOHIDEvent.h>
#include <IOKit/hid/IOHIDEventSystemClient.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <mach/mach_time.h>

#define IOFIXED(v) ((SInt32)((v) * 65536.0))

int main(int argc, char **argv) {
    if (argc != 5) {
        printf("usage: %s <0=down|1=move|2=up> <x> <y> <finger>\n", argv[0]);
        return 1;
    }
    int type = atoi(argv[1]);
    float x = atof(argv[2]);
    float y = atof(argv[3]);
    int finger = atoi(argv[4]);

    IOHIDEventSystemClientRef client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (!client) { printf("no client\n"); return 1; }

    IOHIDEventRef parent = IOHIDEventCreateDigitizerEvent(
        kCFAllocatorDefault, mach_absolute_time(),
        3, 0, 2, 0x01, 0, 0, 0, 0, 0, 0, 1, 0, 0);

    IOHIDEventRef event = IOHIDEventCreateDigitizerFingerEvent(
        kCFAllocatorDefault, mach_absolute_time(),
        finger, 2,
        (type == 2 ? 0x01 : 0x01 | 0x02 | 0x04),
        IOFIXED(x), IOFIXED(y), 0,
        IOFIXED(type == 2 ? 0.0 : 1.0), 0,
        type != 2, type != 2, 0);

    IOHIDEventAppendEvent(parent, event);
    IOHIDEventSystemClientDispatchEvent(client, parent);

    CFRelease(event);
    CFRelease(parent);
    CFRelease(client);
    printf("OK\n");
    return 0;
}
