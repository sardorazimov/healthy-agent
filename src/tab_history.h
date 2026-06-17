#ifndef TAB_HISTORY_H
#define TAB_HISTORY_H

#include "agent.h"

#import <Cocoa/Cocoa.h>

@interface MiransasHistoryTab : NSView
- (void)updateWithSnapshot:(const agent_snapshot_t *)snapshot;
@end

#endif
