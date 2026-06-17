#ifndef TAB_STORAGE_H
#define TAB_STORAGE_H

#include "agent.h"

#import <Cocoa/Cocoa.h>

@interface MiransasStorageTab : NSView
- (void)updateWithSnapshot:(const agent_snapshot_t *)snapshot;
@end

#endif
