#import "history_ring.h"

#include <stdlib.h>
#include <string.h>

// 24h at the current 2s tick = 43200 samples; round up for safety.
#define MIRANSAS_RING_CAPACITY 50000

@implementation MiransasHistoryRing {
    miransas_history_sample_t *_buffer;
    NSUInteger _capacity;
    NSUInteger _head;   // next write index
    NSUInteger _count;  // number of valid samples (capped at _capacity)
}

+ (instancetype)shared {
    static MiransasHistoryRing *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[MiransasHistoryRing alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _capacity = MIRANSAS_RING_CAPACITY;
    _buffer = calloc(_capacity, sizeof(miransas_history_sample_t));
    _head = 0;
    _count = 0;
    return self;
}

- (void)appendCPU:(double)cpuPercent
      ramFraction:(double)ramFraction
     diskFraction:(double)diskFraction {
    miransas_history_sample_t s;
    s.timestamp = time(NULL);
    s.cpu_percent  = cpuPercent;
    s.ram_fraction = ramFraction;
    s.disk_fraction = diskFraction;

    _buffer[_head] = s;
    _head = (_head + 1) % _capacity;
    if (_count < _capacity) _count++;
}

- (NSUInteger)copySamplesSince:(time_t)since
                            into:(miransas_history_sample_t *)out
                        capacity:(NSUInteger)capacity {
    if (!out || capacity == 0 || _count == 0) return 0;

    NSUInteger start = (_count == _capacity) ? _head : 0;
    NSUInteger copied = 0;

    for (NSUInteger i = 0; i < _count && copied < capacity; i++) {
        NSUInteger idx = (start + i) % _capacity;
        if (_buffer[idx].timestamp >= since) {
            out[copied++] = _buffer[idx];
        }
    }
    return copied;
}

- (NSUInteger)totalSamples {
    return _count;
}

- (time_t)oldestTimestamp {
    if (_count == 0) return 0;
    NSUInteger start = (_count == _capacity) ? _head : 0;
    return _buffer[start].timestamp;
}

- (time_t)newestTimestamp {
    if (_count == 0) return 0;
    NSUInteger idx = (_head == 0) ? (_capacity - 1) : (_head - 1);
    return _buffer[idx].timestamp;
}

@end
