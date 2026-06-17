#import "tab_history.h"
#import "history_ring.h"

#pragma mark - Chart view

@interface MiransasChartView : NSView
@property(nonatomic, copy)   NSString *chartTitle;
@property(nonatomic, strong) NSColor *lineColor;
- (void)setSamples:(const double *)values  // 0..100
            count:(NSUInteger)count
       windowStart:(time_t)windowStart
         windowEnd:(time_t)windowEnd
       timestamps:(const time_t *)timestamps;
@end

@implementation MiransasChartView {
    NSTextField *_titleField;
    NSTextField *_statsField;
    double *_values;
    time_t *_times;
    NSUInteger _count;
    time_t _windowStart;
    time_t _windowEnd;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (!self) return nil;
    self.wantsLayer = YES;
    _lineColor = [[NSColor systemBlueColor] retain];

    _titleField = [[NSTextField alloc] init];
    [_titleField setBezeled:NO];
    [_titleField setDrawsBackground:NO];
    [_titleField setEditable:NO];
    [_titleField setSelectable:NO];
    [_titleField setFont:[NSFont systemFontOfSize:11.0 weight:NSFontWeightSemibold]];
    [_titleField setTextColor:[NSColor secondaryLabelColor]];
    [self addSubview:_titleField];

    _statsField = [[NSTextField alloc] init];
    [_statsField setBezeled:NO];
    [_statsField setDrawsBackground:NO];
    [_statsField setEditable:NO];
    [_statsField setSelectable:NO];
    [_statsField setAlignment:NSTextAlignmentRight];
    [_statsField setFont:[NSFont monospacedDigitSystemFontOfSize:11.0
                                                          weight:NSFontWeightRegular]];
    [_statsField setTextColor:[NSColor tertiaryLabelColor]];
    [_statsField setStringValue:@"no data"];
    [self addSubview:_statsField];

    return self;
}

- (void)dealloc {
    [_chartTitle release];
    [_lineColor release];
    free(_values);
    free(_times);
    [super dealloc];
}

- (void)setChartTitle:(NSString *)chartTitle {
    [_chartTitle release];
    _chartTitle = [chartTitle copy];
    [_titleField setStringValue:[chartTitle uppercaseString] ?: @""];
}

- (void)setLineColor:(NSColor *)lineColor {
    [_lineColor release];
    _lineColor = [lineColor retain];
    [self setNeedsDisplay:YES];
}

- (void)setSamples:(const double *)values
            count:(NSUInteger)count
       windowStart:(time_t)windowStart
         windowEnd:(time_t)windowEnd
       timestamps:(const time_t *)timestamps {
    free(_values); _values = NULL;
    free(_times);  _times  = NULL;
    _count = count;
    _windowStart = windowStart;
    _windowEnd   = windowEnd;

    if (count > 0 && values && timestamps) {
        _values = malloc(sizeof(double) * count);
        _times  = malloc(sizeof(time_t) * count);
        memcpy(_values, values,     sizeof(double) * count);
        memcpy(_times,  timestamps, sizeof(time_t) * count);

        double vmin = values[0], vmax = values[0], vsum = 0.0;
        for (NSUInteger i = 0; i < count; i++) {
            double v = values[i];
            if (v < vmin) vmin = v;
            if (v > vmax) vmax = v;
            vsum += v;
        }
        double vavg = vsum / (double)count;
        [_statsField setStringValue:
            [NSString stringWithFormat:@"min %.0f  ·  avg %.0f  ·  max %.0f",
             vmin, vavg, vmax]];
    } else {
        [_statsField setStringValue:@"no data"];
    }

    [self setNeedsDisplay:YES];
}

- (void)layout {
    [super layout];
    NSRect b = self.bounds;
    CGFloat headerH = 14.0;
    _titleField.frame = NSMakeRect(0.0, b.size.height - headerH, b.size.width / 2.0, headerH);
    _statsField.frame = NSMakeRect(b.size.width / 2.0, b.size.height - headerH,
                                   b.size.width / 2.0, headerH);
}

- (NSRect)chartRect {
    NSRect b = self.bounds;
    CGFloat headerH = 14.0;
    CGFloat gap = 4.0;
    CGFloat top = b.size.height - headerH - gap;
    CGFloat bottom = 2.0;
    return NSMakeRect(0.0, bottom, b.size.width, top - bottom);
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSRect chart = [self chartRect];

    // Frame background
    NSBezierPath *bg = [NSBezierPath bezierPathWithRoundedRect:chart
                                                       xRadius:6.0 yRadius:6.0];
    [[[NSColor labelColor] colorWithAlphaComponent:0.04] setFill];
    [bg fill];

    // Gridline at 50%
    NSBezierPath *grid = [NSBezierPath bezierPath];
    CGFloat midY = NSMinY(chart) + chart.size.height * 0.5;
    [grid moveToPoint:NSMakePoint(NSMinX(chart) + 6.0, midY)];
    [grid lineToPoint:NSMakePoint(NSMaxX(chart) - 6.0, midY)];
    [grid setLineWidth:0.5];
    CGFloat dash[2] = {2.0, 3.0};
    [grid setLineDash:dash count:2 phase:0.0];
    [[[NSColor labelColor] colorWithAlphaComponent:0.10] setStroke];
    [grid stroke];

    if (_count < 2 || _windowEnd <= _windowStart) {
        NSString *msg = (_count == 0) ? @"Collecting samples…" : @"Need more samples";
        NSDictionary *attrs = @{
            NSFontAttributeName: [NSFont systemFontOfSize:11.0
                                                   weight:NSFontWeightRegular],
            NSForegroundColorAttributeName: [NSColor tertiaryLabelColor]
        };
        NSSize sz = [msg sizeWithAttributes:attrs];
        [msg drawAtPoint:NSMakePoint(NSMidX(chart) - sz.width / 2.0,
                                     NSMidY(chart) - sz.height / 2.0)
          withAttributes:attrs];
        return;
    }

    CGFloat padX = 6.0;
    CGFloat padY = 4.0;
    CGFloat plotW = chart.size.width - 2.0 * padX;
    CGFloat plotH = chart.size.height - 2.0 * padY;
    CGFloat originX = NSMinX(chart) + padX;
    CGFloat originY = NSMinY(chart) + padY;

    double span = (double)(_windowEnd - _windowStart);
    if (span <= 0.0) span = 1.0;

    NSBezierPath *line = [NSBezierPath bezierPath];
    NSBezierPath *fill = [NSBezierPath bezierPath];
    BOOL started = NO;
    CGFloat lastX = originX;

    for (NSUInteger i = 0; i < _count; i++) {
        double tFrac = (double)(_times[i] - _windowStart) / span;
        if (tFrac < 0.0) tFrac = 0.0;
        if (tFrac > 1.0) tFrac = 1.0;
        double vClamped = _values[i];
        if (vClamped < 0.0)   vClamped = 0.0;
        if (vClamped > 100.0) vClamped = 100.0;

        CGFloat x = originX + (CGFloat)(tFrac * plotW);
        CGFloat y = originY + (CGFloat)((vClamped / 100.0) * plotH);
        NSPoint p = NSMakePoint(x, y);

        if (!started) {
            [line moveToPoint:p];
            [fill moveToPoint:NSMakePoint(x, originY)];
            [fill lineToPoint:p];
            started = YES;
        } else {
            [line lineToPoint:p];
            [fill lineToPoint:p];
        }
        lastX = x;
    }

    if (started) {
        [fill lineToPoint:NSMakePoint(lastX, originY)];
        [fill closePath];
        [[_lineColor colorWithAlphaComponent:0.18] setFill];
        [fill fill];

        [line setLineWidth:1.5];
        [line setLineJoinStyle:NSLineJoinStyleRound];
        [_lineColor setStroke];
        [line stroke];
    }
}

@end

#pragma mark - History tab

@interface MiransasHistoryTab ()
- (void)rangeChanged:(NSSegmentedControl *)sender;
@end

@implementation MiransasHistoryTab {
    NSSegmentedControl *_rangeSelector;
    MiransasChartView  *_cpuChart;
    MiransasChartView  *_ramChart;
    MiransasChartView  *_diskChart;
    NSInteger _rangeSeconds;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (!self) return nil;
    self.wantsLayer = YES;
    self.layer.backgroundColor = [[NSColor windowBackgroundColor] CGColor];

    _rangeSeconds = 24 * 3600;

    _rangeSelector = [NSSegmentedControl
        segmentedControlWithLabels:@[@"1h", @"6h", @"24h"]
                      trackingMode:NSSegmentSwitchTrackingSelectOne
                            target:self
                            action:@selector(rangeChanged:)];
    [_rangeSelector setSegmentStyle:NSSegmentStyleAutomatic];
    [_rangeSelector setSelectedSegment:2];
    [self addSubview:_rangeSelector];

    _cpuChart  = [[MiransasChartView alloc] initWithFrame:NSZeroRect];
    _cpuChart.chartTitle = @"CPU %";
    _cpuChart.lineColor  = [NSColor systemBlueColor];
    [self addSubview:_cpuChart];

    _ramChart  = [[MiransasChartView alloc] initWithFrame:NSZeroRect];
    _ramChart.chartTitle = @"RAM %";
    _ramChart.lineColor  = [NSColor systemPurpleColor];
    [self addSubview:_ramChart];

    _diskChart = [[MiransasChartView alloc] initWithFrame:NSZeroRect];
    _diskChart.chartTitle = @"DISK %";
    _diskChart.lineColor  = [NSColor systemTealColor];
    [self addSubview:_diskChart];

    return self;
}

- (void)layout {
    [super layout];
    NSRect b = self.bounds;
    CGFloat pad = 24.0;
    CGFloat selectorH = 24.0;
    CGFloat sectionGap = 14.0;
    CGFloat innerW = b.size.width - 2.0 * pad;

    NSSize segSize = [_rangeSelector intrinsicContentSize];
    if (segSize.width < 160.0) segSize.width = 160.0;
    _rangeSelector.frame = NSMakeRect(pad,
                                      b.size.height - pad - selectorH,
                                      segSize.width,
                                      selectorH);

    CGFloat chartsAreaTop = b.size.height - pad - selectorH - sectionGap;
    CGFloat chartsAreaH = chartsAreaTop - pad;
    CGFloat chartH = (chartsAreaH - 2.0 * sectionGap) / 3.0;
    if (chartH < 60.0) chartH = 60.0;

    _cpuChart.frame  = NSMakeRect(pad, chartsAreaTop - chartH, innerW, chartH);
    _ramChart.frame  = NSMakeRect(pad,
                                  chartsAreaTop - 2.0 * chartH - sectionGap,
                                  innerW, chartH);
    _diskChart.frame = NSMakeRect(pad,
                                  chartsAreaTop - 3.0 * chartH - 2.0 * sectionGap,
                                  innerW, chartH);
}

- (void)rangeChanged:(NSSegmentedControl *)sender {
    switch (sender.selectedSegment) {
        case 0: _rangeSeconds = 3600;       break;
        case 1: _rangeSeconds = 6 * 3600;   break;
        default: _rangeSeconds = 24 * 3600; break;
    }
    [self refreshFromRing];
}

- (void)updateWithSnapshot:(const agent_snapshot_t *)snapshot {
    (void)snapshot;
    [self refreshFromRing];
}

- (void)refreshFromRing {
    MiransasHistoryRing *ring = [MiransasHistoryRing shared];
    NSUInteger total = [ring totalSamples];
    if (total == 0) {
        [_cpuChart  setSamples:NULL count:0 windowStart:0 windowEnd:0 timestamps:NULL];
        [_ramChart  setSamples:NULL count:0 windowStart:0 windowEnd:0 timestamps:NULL];
        [_diskChart setSamples:NULL count:0 windowStart:0 windowEnd:0 timestamps:NULL];
        return;
    }

    time_t now = time(NULL);
    time_t since = now - (time_t)_rangeSeconds;

    miransas_history_sample_t *buf = malloc(sizeof(miransas_history_sample_t) * total);
    NSUInteger n = [ring copySamplesSince:since into:buf capacity:total];

    if (n == 0) {
        [_cpuChart  setSamples:NULL count:0 windowStart:0 windowEnd:0 timestamps:NULL];
        [_ramChart  setSamples:NULL count:0 windowStart:0 windowEnd:0 timestamps:NULL];
        [_diskChart setSamples:NULL count:0 windowStart:0 windowEnd:0 timestamps:NULL];
        free(buf);
        return;
    }

    double *cpu  = malloc(sizeof(double) * n);
    double *ram  = malloc(sizeof(double) * n);
    double *disk = malloc(sizeof(double) * n);
    time_t *ts   = malloc(sizeof(time_t) * n);

    for (NSUInteger i = 0; i < n; i++) {
        cpu[i]  = buf[i].cpu_percent;
        ram[i]  = buf[i].ram_fraction  * 100.0;
        disk[i] = buf[i].disk_fraction * 100.0;
        ts[i]   = buf[i].timestamp;
    }

    [_cpuChart  setSamples:cpu  count:n windowStart:since windowEnd:now timestamps:ts];
    [_ramChart  setSamples:ram  count:n windowStart:since windowEnd:now timestamps:ts];
    [_diskChart setSamples:disk count:n windowStart:since windowEnd:now timestamps:ts];

    free(cpu);
    free(ram);
    free(disk);
    free(ts);
    free(buf);
}

@end
