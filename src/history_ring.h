#ifndef HISTORY_RING_H
#define HISTORY_RING_H

#include <time.h>

#import <Foundation/Foundation.h>

typedef struct {
    time_t timestamp;
    double cpu_percent;   // 0..100
    double ram_fraction;  // 0..1
    double disk_fraction; // 0..1
} miransas_history_sample_t;

@interface MiransasHistoryRing : NSObject

+ (instancetype)shared;

- (void)appendCPU:(double)cpuPercent
      ramFraction:(double)ramFraction
     diskFraction:(double)diskFraction;

- (NSUInteger)copySamplesSince:(time_t)since
                            into:(miransas_history_sample_t *)out
                        capacity:(NSUInteger)capacity;

- (NSUInteger)totalSamples;
- (time_t)oldestTimestamp;
- (time_t)newestTimestamp;

@end

#endif
