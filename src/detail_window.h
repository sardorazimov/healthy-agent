#ifndef DETAIL_WINDOW_H
#define DETAIL_WINDOW_H

#include "agent.h"

#import <Cocoa/Cocoa.h>

@interface MiransasDetailWindow : NSObject

+ (instancetype)shared;

- (void)show;
- (void)updateWithSnapshot:(const agent_snapshot_t *)snapshot;

@end

#endif
