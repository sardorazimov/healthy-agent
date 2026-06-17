#ifndef TAB_NETWORK_H
#define TAB_NETWORK_H

#include "agent.h"

#import <Cocoa/Cocoa.h>

@interface MiransasNetworkSampler : NSObject
+ (instancetype)shared;
- (void)sample;

- (double)rxRateKBs;
- (double)txRateKBs;
- (uint64_t)sessionRxBytes;
- (uint64_t)sessionTxBytes;
- (NSString *)primaryInterface;
- (NSString *)primaryIPv4;
- (BOOL)wifiPresent;
- (BOOL)wifiPowerOn;
- (BOOL)wifiAssociated;
- (NSString *)wifiSSID;
- (NSInteger)wifiRSSI;
@end

@interface MiransasNetworkTab : NSView
- (void)updateWithSnapshot:(const agent_snapshot_t *)snapshot;
@end

#endif
