#ifndef TAB_OVERVIEW_H
#define TAB_OVERVIEW_H

#include "agent.h"

#import <Cocoa/Cocoa.h>

@interface MiransasOverviewTab : NSView
- (void)updateWithSnapshot:(const agent_snapshot_t *)snapshot;
@end

#endif
