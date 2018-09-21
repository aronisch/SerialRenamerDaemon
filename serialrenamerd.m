//
//  serialrenamerd.m
//  SerialRenamerDaemon
//
//  Created by Arthur Rönisch on 18/09/2018.
//  Copyright © 2018 Arthur Rönisch. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <IOKit/serial/IOSerialKeys.h>

#include <ftw.h>

#define MAX_STR_SIZE 80
#define BUFSIZE 60

NSMutableDictionary *linkedDevices;

char* getUUIDFromSerialDevice(const char* path){
    FILE *fp;
    char cmd[200] = "robot getuuid ";
    strcat(cmd, path);
    char *buf = (char*)malloc(sizeof(char)*BUFSIZE);

    if ((fp = popen(cmd, "r")) == NULL) {
        NSLog(@"Error running robot getuuid");
        return NULL;
    }

    fgets(buf, BUFSIZE, fp);

    if(pclose(fp))  {
        NSLog(@"Command exited with error status");
        return NULL;
    }

    return buf;
}

void createSymlinkFromPathWithName(const char *path, const char *name) {
    char newPath[MAX_STR_SIZE];
    strcat(newPath, "/tmp/arduino/");
    if(strlen(newPath) + strlen(name) < MAX_STR_SIZE){
        strcat(newPath, name);
        strtok(newPath, "\n");
        int err = symlink(path, newPath);
        if(err == -1){
            NSLog(@"symlink() failed : %s", strerror(errno));
        } else {
            [linkedDevices setObject:[NSString stringWithCString:newPath encoding:NSASCIIStringEncoding]
                              forKey:[NSString stringWithCString:path encoding:NSASCIIStringEncoding]];
        }
    } else {
        NSLog(@"createSymlinkFromPathWithName : Name too long");
    }
}

void removeCorrespondingSymlink(const char *path){
    NSString *key = [NSString stringWithCString:path encoding:NSASCIIStringEncoding];
    NSString *symlinkPath = [linkedDevices objectForKey:key];
    if(symlinkPath){
        int err = unlink([symlinkPath cStringUsingEncoding:NSASCIIStringEncoding]);
        if(err == -1){
            NSLog(@"unlink() failed : %s", strerror(errno));
        } else {
            [linkedDevices removeObjectForKey:key];
        }
    }
}

void serialDeviceAdded(void *refCon, io_iterator_t iterator){
    io_iterator_t serialDevice;
    while ((serialDevice = IOIteratorNext(iterator))) {
        CFStringRef deviceBSDName_cf = (CFStringRef) IORegistryEntrySearchCFProperty (serialDevice,
                                                                                      kIOServicePlane,
                                                                                      CFSTR (kIODialinDeviceKey),
                                                                                      kCFAllocatorDefault,
                                                                                      kIORegistryIterateRecursively );
        const char *devicePath = CFStringGetCStringPtr(deviceBSDName_cf, kCFStringEncodingMacRoman);
        NSLog(@"Matching Serial device appeared with path: %s", devicePath);
        const char *uuid = getUUIDFromSerialDevice(devicePath);
        if(uuid != NULL){
            NSLog(@"Creating symlink with uuid : %s", uuid);
            createSymlinkFromPathWithName(devicePath, uuid);
        }
    };
}
void serialDeviceRemoved(void *refCon, io_iterator_t iterator){
    io_iterator_t serialDevice;
    while ((serialDevice = IOIteratorNext(iterator))) {
        CFStringRef deviceBSDName_cf = (CFStringRef) IORegistryEntrySearchCFProperty (serialDevice,
                                                                                      kIOServicePlane,
                                                                                      CFSTR (kIODialinDeviceKey),
                                                                                      kCFAllocatorDefault,
                                                                                      kIORegistryIterateRecursively );
        const char *devicePath = CFStringGetCStringPtr(deviceBSDName_cf, kCFStringEncodingMacRoman);
        NSLog(@"Matching Serial device disappeared from path: %s", devicePath);
        removeCorrespondingSymlink(devicePath);
    };
}

int removeFiles(const char *pathname, const struct stat *sbuf, int type, struct FTW *ftwb)
{
    if(remove(pathname) < 0)
    {
        NSLog(@"remove() failed : %s", strerror(errno));
        return -1;
    }
    return 0;
}

int clearDirectory(const char *dir){
    if (nftw(dir, removeFiles,10, FTW_DEPTH|FTW_MOUNT|FTW_PHYS) < 0)
    {
        if(errno != ENOENT){
            NSLog(@"nftw() failed : %s", strerror(errno));
            return -1;
        }
        return 0;
    }
    return -1;
}

int main(int argc, char const *argv[]) {
    @autoreleasepool{
        NSLog(@"Starting serialrenamerd...");

        //Remove all the link in the arduino folder and the folder itself
        if(clearDirectory("/tmp/arduino/") == -1){
            NSLog(@"clearDirectory() failed");
            exit(EXIT_FAILURE);
        }

        //Re-create arduino folder
        if(mkdir("/tmp/arduino", 0777) == -1){
            NSLog(@"mkdir() failed : %s", strerror(errno));
            exit(EXIT_FAILURE);
        }

        //Dictionary to keep the serial devices currently linked
        linkedDevices = [NSMutableDictionary dictionary];

        io_iterator_t portIterator;
        mach_port_t masterPort;
        IOMasterPort(MACH_PORT_NULL, &masterPort);

        //Creating dictionary to match the serial devices
        CFMutableDictionaryRef matchingDict = IOServiceMatching(kIOSerialBSDServiceValue);
        CFDictionaryAddValue(matchingDict, CFSTR(kIOSerialBSDTypeKey), CFSTR(kIOSerialBSDRS232Type));

        NSLog(@"Adding notifications for serial device appearance...");
        // Set up notification port and add it to the current run loop for addition notifications.
        IONotificationPortRef notificationPort = IONotificationPortCreate(masterPort);
        CFRunLoopAddSource(CFRunLoopGetCurrent(),
                           IONotificationPortGetRunLoopSource(notificationPort),
                           kCFRunLoopDefaultMode);

        // Register for notifications when a serial port is added to the system.
        // Retain dictionary first because all IOServiceMatching calls consume dictionary.
        CFRetain(matchingDict);
        kern_return_t result = IOServiceAddMatchingNotification(notificationPort,
                                                                kIOMatchedNotification,
                                                                matchingDict,
                                                                serialDeviceAdded,
                                                                nil,
                                                                &portIterator);
        if(result != KERN_SUCCESS){
            NSLog(@"Error - IOServiceAddMatchingNotification returned : %i", result);
            exit(EXIT_FAILURE);
        }
        // Run out the iterator or notifications won't start.
        while (IOIteratorNext(portIterator)) {};

        NSLog(@"Adding notifications for serial device disappearance...");

        // Also Set up notification port and add it to the current run loop removal notifications.
        IONotificationPortRef terminationNotificationPort = IONotificationPortCreate(kIOMasterPortDefault);
        CFRunLoopAddSource(CFRunLoopGetCurrent(),
                           IONotificationPortGetRunLoopSource(terminationNotificationPort),
                           kCFRunLoopDefaultMode);

        // Register for notifications when a serial port is added to the system.
        // Retain dictionary first because all IOServiceMatching calls consume dictionary.
        CFRetain(matchingDict);
        kern_return_t result1 = IOServiceAddMatchingNotification(terminationNotificationPort,
                                                  kIOTerminatedNotification,
                                                  matchingDict,
                                                  serialDeviceRemoved,
                                                  nil,
                                                  &portIterator);
        if(result1 != KERN_SUCCESS){
          NSLog(@"Error - IOServiceAddMatchingNotification returned : %i", result);
          exit(EXIT_FAILURE);
        }
        // Run out the iterator or notifications won't start.
        while (IOIteratorNext(portIterator)) {};
        CFRetain(matchingDict);
        NSLog(@"Daemon ready !");

        CFRunLoopRun();
    }

    return EXIT_SUCCESS;
}
