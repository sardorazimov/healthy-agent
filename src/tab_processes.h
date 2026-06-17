#ifndef TAB_PROCESSES_H
#define TAB_PROCESSES_H

#include "agent.h"

#import <Cocoa/Cocoa.h>

@interface MiransasProcessesTab : NSView
- (void)updateWithSnapshot:(const agent_snapshot_t *)snapshot;
@end

#endif
