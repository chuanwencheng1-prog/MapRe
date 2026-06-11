//
//  KernelPanel-Bridging-Header.h
//  KernelPanel
//

@import UIKit;
#import <Foundation/Foundation.h>

#import "darksword.h"
#import "offsets.h"
#import "utils.h"
#import "vnode.h"
#import "apfs.h"
#import "vfs.h"
#import "sbx.h"
#import "rc.h"
#import "RemoteCall.h"
#import "decrypt.h"
#import "persistence.h"
#import "ota.h"
#import "screentime.h"

#import <zlib.h>

long findcachedataoff(const char *mgkey);

@interface UIDevice(Private)
+ (BOOL)_hasHomeButton;
@end
