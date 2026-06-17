#import "tab_overview.h"

#include <sys/mount.h>
#include <sys/param.h>

#import <IOKit/IOKitLib.h>
#import <IOKit/ps/IOPowerSources.h>
#import <IOKit/ps/IOPSKeys.h>

#pragma mark - Helpers

static NSColor *score_color(int score) {
    if (score > 70) return [NSColor systemGreenColor];
    if (score >= 40) return [NSColor systemOrangeColor];
    return [NSColor systemRedColor];
}

static NSColor *load_color(double fraction) {
    if (fraction >= 0.85) return [NSColor systemRedColor];
    if (fraction >= 0.65) return [NSColor systemOrangeColor];
    return [NSColor systemBlueColor];
}

#pragma mark - Score gauge

@interface MiransasScoreGauge : NSView
@property(nonatomic, assign) int score;
@end

@implementation MiransasScoreGauge {
    NSTextField *_scoreField;
    NSTextField *_captionField;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (!self) return nil;
    _score = -1;
    self.wantsLayer = YES;

    _scoreField = [[NSTextField alloc] init];
    [_scoreField setBezeled:NO];
    [_scoreField setDrawsBackground:NO];
    [_scoreField setEditable:NO];
    [_scoreField setSelectable:NO];
    [_scoreField setAlignment:NSTextAlignmentCenter];
    [_scoreField setFont:[NSFont systemFontOfSize:46.0 weight:NSFontWeightBold]];
    [_scoreField setStringValue:@"--"];
    [_scoreField setTextColor:[NSColor labelColor]];
    [self addSubview:_scoreField];

    _captionField = [[NSTextField alloc] init];
    [_captionField setBezeled:NO];
    [_captionField setDrawsBackground:NO];
    [_captionField setEditable:NO];
    [_captionField setSelectable:NO];
    [_captionField setAlignment:NSTextAlignmentCenter];
    [_captionField setFont:[NSFont systemFontOfSize:10.0 weight:NSFontWeightSemibold]];
    [_captionField setStringValue:@"HEALTH SCORE"];
    [_captionField setTextColor:[NSColor secondaryLabelColor]];
    [self addSubview:_captionField];

    return self;
}

- (BOOL)isFlipped { return NO; }

- (void)layout {
    [super layout];
    NSRect b = self.bounds;
    CGFloat scoreH = 54.0;
    CGFloat captionH = 14.0;
    CGFloat gap = 4.0;
    CGFloat blockH = scoreH + gap + captionH;
    CGFloat originY = (b.size.height - blockH) / 2.0;

    _scoreField.frame = NSMakeRect(0.0, originY + captionH + gap, b.size.width, scoreH);
    _captionField.frame = NSMakeRect(0.0, originY, b.size.width, captionH);
}

- (void)setScore:(int)score {
    _score = score;
    if (score < 0) {
        [_scoreField setStringValue:@"--"];
        [_scoreField setTextColor:[NSColor labelColor]];
    } else {
        [_scoreField setStringValue:[NSString stringWithFormat:@"%d", score]];
        [_scoreField setTextColor:score_color(score)];
    }
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSRect r = self.bounds;
    CGFloat side = MIN(r.size.width, r.size.height);
    CGFloat lineWidth = 14.0;
    CGFloat radius = side / 2.0 - lineWidth / 2.0 - 2.0;
    if (radius <= 0.0) return;
    NSPoint center = NSMakePoint(NSMidX(r), NSMidY(r));

    NSBezierPath *bg = [NSBezierPath bezierPathWithOvalInRect:
                        NSMakeRect(center.x - radius, center.y - radius,
                                   radius * 2.0, radius * 2.0)];
    [bg setLineWidth:lineWidth];
    [[[NSColor labelColor] colorWithAlphaComponent:0.12] setStroke];
    [bg stroke];

    if (_score > 0) {
        CGFloat fraction = (CGFloat)MIN(MAX(_score, 0), 100) / 100.0;
        CGFloat sweep = 360.0 * fraction;
        NSBezierPath *fg = [NSBezierPath bezierPath];
        [fg appendBezierPathWithArcWithCenter:center
                                       radius:radius
                                   startAngle:90.0
                                     endAngle:(90.0 - sweep)
                                    clockwise:YES];
        [fg setLineWidth:lineWidth];
        [fg setLineCapStyle:NSLineCapStyleRound];
        [score_color(_score) setStroke];
        [fg stroke];
    }
}

@end

#pragma mark - Progress bar

@interface MiransasProgressBar : NSView
@property(nonatomic, copy) NSString *barLabel;
@property(nonatomic, copy) NSString *valueText;
@property(nonatomic, assign) double fraction;
@end

@implementation MiransasProgressBar {
    NSTextField *_labelField;
    NSTextField *_valueField;
    NSView *_barBg;
    NSView *_barFill;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (!self) return nil;
    self.wantsLayer = YES;

    _labelField = [[NSTextField alloc] init];
    [_labelField setBezeled:NO];
    [_labelField setDrawsBackground:NO];
    [_labelField setEditable:NO];
    [_labelField setSelectable:NO];
    [_labelField setFont:[NSFont systemFontOfSize:12.0 weight:NSFontWeightMedium]];
    [_labelField setTextColor:[NSColor secondaryLabelColor]];
    [self addSubview:_labelField];

    _valueField = [[NSTextField alloc] init];
    [_valueField setBezeled:NO];
    [_valueField setDrawsBackground:NO];
    [_valueField setEditable:NO];
    [_valueField setSelectable:NO];
    [_valueField setAlignment:NSTextAlignmentRight];
    [_valueField setFont:[NSFont monospacedDigitSystemFontOfSize:12.0
                                                          weight:NSFontWeightRegular]];
    [_valueField setTextColor:[NSColor labelColor]];
    [self addSubview:_valueField];

    _barBg = [[NSView alloc] init];
    _barBg.wantsLayer = YES;
    _barBg.layer.cornerRadius = 4.0;
    _barBg.layer.backgroundColor = [[[NSColor labelColor] colorWithAlphaComponent:0.10] CGColor];
    [self addSubview:_barBg];

    _barFill = [[NSView alloc] init];
    _barFill.wantsLayer = YES;
    _barFill.layer.cornerRadius = 4.0;
    _barFill.layer.backgroundColor = [[NSColor systemBlueColor] CGColor];
    [_barBg addSubview:_barFill];

    return self;
}

- (void)layout {
    [super layout];
    NSRect b = self.bounds;
    CGFloat topRowH = 16.0;
    CGFloat barH = 8.0;
    CGFloat gap = 6.0;
    CGFloat originY = (b.size.height - topRowH - gap - barH) / 2.0;
    CGFloat halfW = b.size.width / 2.0;

    _labelField.frame = NSMakeRect(0.0, originY + barH + gap, halfW, topRowH);
    _valueField.frame = NSMakeRect(halfW, originY + barH + gap, halfW, topRowH);
    _barBg.frame = NSMakeRect(0.0, originY, b.size.width, barH);

    CGFloat fillW = b.size.width * MIN(MAX(_fraction, 0.0), 1.0);
    _barFill.frame = NSMakeRect(0.0, 0.0, fillW, barH);
}

- (void)setBarLabel:(NSString *)label {
    [_barLabel release];
    _barLabel = [label copy];
    _labelField.stringValue = label ?: @"";
}

- (void)setValueText:(NSString *)valueText {
    [_valueText release];
    _valueText = [valueText copy];
    _valueField.stringValue = valueText ?: @"";
}

- (void)setFraction:(double)fraction {
    _fraction = fraction;
    _barFill.layer.backgroundColor = [load_color(fraction) CGColor];
    [self setNeedsLayout:YES];
}

@end

#pragma mark - Battery

typedef struct {
    BOOL present;
    int percent;
    BOOL charging;
    int cycle_count;
} battery_info_t;

static battery_info_t read_battery_info(void) {
    battery_info_t info;
    info.present = NO;
    info.percent = 0;
    info.charging = NO;
    info.cycle_count = -1;

    CFTypeRef psInfo = IOPSCopyPowerSourcesInfo();
    if (psInfo) {
        CFArrayRef list = IOPSCopyPowerSourcesList(psInfo);
        if (list) {
            if (CFArrayGetCount(list) > 0) {
                CFTypeRef ps = CFArrayGetValueAtIndex(list, 0);
                CFDictionaryRef desc = IOPSGetPowerSourceDescription(psInfo, ps);
                if (desc) {
                    CFNumberRef cur = (CFNumberRef)CFDictionaryGetValue(desc, CFSTR(kIOPSCurrentCapacityKey));
                    CFNumberRef mx  = (CFNumberRef)CFDictionaryGetValue(desc, CFSTR(kIOPSMaxCapacityKey));
                    CFBooleanRef ch = (CFBooleanRef)CFDictionaryGetValue(desc, CFSTR(kIOPSIsChargingKey));
                    int current = 0, maxv = 100;
                    if (cur) CFNumberGetValue(cur, kCFNumberIntType, &current);
                    if (mx)  CFNumberGetValue(mx,  kCFNumberIntType, &maxv);
                    if (maxv > 0) {
                        info.percent = (int)((current * 100) / maxv);
                        info.present = YES;
                    }
                    if (ch) info.charging = CFBooleanGetValue(ch);
                }
            }
            CFRelease(list);
        }
        CFRelease(psInfo);
    }

    io_iterator_t iter = MACH_PORT_NULL;
    if (IOServiceGetMatchingServices(MACH_PORT_NULL,
                                     IOServiceMatching("AppleSmartBattery"),
                                     &iter) == KERN_SUCCESS) {
        io_object_t svc = IOIteratorNext(iter);
        if (svc) {
            CFTypeRef cyc = IORegistryEntryCreateCFProperty(svc, CFSTR("CycleCount"),
                                                            kCFAllocatorDefault, 0);
            if (cyc) {
                if (CFGetTypeID(cyc) == CFNumberGetTypeID()) {
                    int val = 0;
                    CFNumberGetValue((CFNumberRef)cyc, kCFNumberIntType, &val);
                    info.cycle_count = val;
                }
                CFRelease(cyc);
            }
            IOObjectRelease(svc);
        }
        IOObjectRelease(iter);
    }

    return info;
}

@interface MiransasBatteryWidget : NSView
- (void)refresh;
@end

@implementation MiransasBatteryWidget {
    NSTextField *_titleField;
    NSTextField *_percentField;
    NSTextField *_stateField;
    NSTextField *_cycleField;
}

static NSTextField *card_label(NSView *parent, CGFloat size, NSFontWeight weight,
                               NSColor *color, NSTextAlignment alignment) {
    NSTextField *f = [[NSTextField alloc] init];
    [f setBezeled:NO];
    [f setDrawsBackground:NO];
    [f setEditable:NO];
    [f setSelectable:NO];
    [f setAlignment:alignment];
    [f setFont:[NSFont systemFontOfSize:size weight:weight]];
    [f setTextColor:color];
    [parent addSubview:f];
    return f;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (!self) return nil;
    self.wantsLayer = YES;
    self.layer.cornerRadius = 10.0;
    self.layer.backgroundColor = [[[NSColor labelColor] colorWithAlphaComponent:0.05] CGColor];

    _titleField   = card_label(self, 11.0, NSFontWeightSemibold,
                               [NSColor secondaryLabelColor], NSTextAlignmentLeft);
    _percentField = card_label(self, 28.0, NSFontWeightBold,
                               [NSColor labelColor],          NSTextAlignmentLeft);
    _stateField   = card_label(self, 12.0, NSFontWeightRegular,
                               [NSColor secondaryLabelColor], NSTextAlignmentLeft);
    _cycleField   = card_label(self, 11.0, NSFontWeightRegular,
                               [NSColor tertiaryLabelColor],  NSTextAlignmentLeft);

    [_titleField   setStringValue:@"BATTERY"];
    [_percentField setStringValue:@"--%"];
    [_stateField   setStringValue:@""];
    [_cycleField   setStringValue:@""];

    return self;
}

- (void)layout {
    [super layout];
    NSRect b = self.bounds;
    CGFloat pad = 12.0;
    CGFloat innerW = b.size.width - 2.0 * pad;

    _titleField.frame   = NSMakeRect(pad, b.size.height - pad - 13.0, innerW, 13.0);
    _percentField.frame = NSMakeRect(pad, b.size.height - pad - 13.0 - 4.0 - 32.0, innerW, 32.0);
    _stateField.frame   = NSMakeRect(pad, pad + 14.0 + 2.0, innerW, 14.0);
    _cycleField.frame   = NSMakeRect(pad, pad, innerW, 14.0);
}

- (void)refresh {
    battery_info_t info = read_battery_info();
    if (!info.present) {
        [_percentField setStringValue:@"N/A"];
        [_stateField   setStringValue:@"No battery"];
        [_cycleField   setStringValue:@""];
        return;
    }
    [_percentField setStringValue:[NSString stringWithFormat:@"%d%%", info.percent]];
    [_stateField   setStringValue:info.charging ? @"Charging" : @"On battery"];
    if (info.cycle_count >= 0) {
        [_cycleField setStringValue:[NSString stringWithFormat:@"Cycle count %d",
                                     info.cycle_count]];
    } else {
        [_cycleField setStringValue:@"Cycle count —"];
    }
}

@end

#pragma mark - Thermal

@interface MiransasThermalWidget : NSView
- (void)refresh;
@end

@implementation MiransasThermalWidget {
    NSTextField *_titleField;
    NSView *_badge;
    NSTextField *_badgeLabel;
    NSTextField *_descField;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (!self) return nil;
    self.wantsLayer = YES;
    self.layer.cornerRadius = 10.0;
    self.layer.backgroundColor = [[[NSColor labelColor] colorWithAlphaComponent:0.05] CGColor];

    _titleField = card_label(self, 11.0, NSFontWeightSemibold,
                             [NSColor secondaryLabelColor], NSTextAlignmentLeft);
    [_titleField setStringValue:@"THERMAL"];

    _badge = [[NSView alloc] init];
    _badge.wantsLayer = YES;
    _badge.layer.cornerRadius = 6.0;
    _badge.layer.backgroundColor = [[NSColor systemGreenColor] CGColor];
    [self addSubview:_badge];

    _badgeLabel = [[NSTextField alloc] init];
    [_badgeLabel setBezeled:NO];
    [_badgeLabel setDrawsBackground:NO];
    [_badgeLabel setEditable:NO];
    [_badgeLabel setSelectable:NO];
    [_badgeLabel setAlignment:NSTextAlignmentCenter];
    [_badgeLabel setStringValue:@"Nominal"];
    [_badgeLabel setFont:[NSFont systemFontOfSize:14.0 weight:NSFontWeightSemibold]];
    [_badgeLabel setTextColor:[NSColor whiteColor]];
    [_badge addSubview:_badgeLabel];

    _descField = card_label(self, 11.0, NSFontWeightRegular,
                            [NSColor tertiaryLabelColor], NSTextAlignmentLeft);
    [_descField setStringValue:@"NSProcessInfo thermal state"];

    return self;
}

- (void)layout {
    [super layout];
    NSRect b = self.bounds;
    CGFloat pad = 12.0;
    CGFloat innerW = b.size.width - 2.0 * pad;
    CGFloat badgeH = 32.0;
    CGFloat badgeY = (b.size.height - badgeH) / 2.0 - 4.0;

    _titleField.frame = NSMakeRect(pad, b.size.height - pad - 13.0, innerW, 13.0);
    _badge.frame      = NSMakeRect(pad, badgeY, innerW, badgeH);
    _badgeLabel.frame = NSMakeRect(0.0, (badgeH - 18.0) / 2.0, innerW, 18.0);
    _descField.frame  = NSMakeRect(pad, pad, innerW, 13.0);
}

- (void)refresh {
    NSProcessInfoThermalState state = [[NSProcessInfo processInfo] thermalState];
    NSString *text;
    NSColor *color;
    switch (state) {
        case NSProcessInfoThermalStateNominal:
            text = @"Nominal";  color = [NSColor systemGreenColor];  break;
        case NSProcessInfoThermalStateFair:
            text = @"Fair";     color = [NSColor systemYellowColor]; break;
        case NSProcessInfoThermalStateSerious:
            text = @"Serious";  color = [NSColor systemOrangeColor]; break;
        case NSProcessInfoThermalStateCritical:
            text = @"Critical"; color = [NSColor systemRedColor];    break;
        default:
            text = @"Unknown";  color = [NSColor systemGrayColor];   break;
    }
    [_badgeLabel setStringValue:text];
    _badge.layer.backgroundColor = [color CGColor];
}

@end

#pragma mark - Overview tab

@implementation MiransasOverviewTab {
    MiransasScoreGauge    *_gauge;
    MiransasProgressBar   *_cpuBar;
    MiransasProgressBar   *_ramBar;
    MiransasProgressBar   *_diskBar;
    MiransasBatteryWidget *_battery;
    MiransasThermalWidget *_thermal;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (!self) return nil;
    self.wantsLayer = YES;
    self.layer.backgroundColor = [[NSColor windowBackgroundColor] CGColor];

    _gauge = [[MiransasScoreGauge alloc] initWithFrame:NSZeroRect];
    [self addSubview:_gauge];

    _cpuBar = [[MiransasProgressBar alloc] initWithFrame:NSZeroRect];
    _cpuBar.barLabel = @"CPU";
    _cpuBar.valueText = @"--";
    [self addSubview:_cpuBar];

    _ramBar = [[MiransasProgressBar alloc] initWithFrame:NSZeroRect];
    _ramBar.barLabel = @"RAM";
    _ramBar.valueText = @"--";
    [self addSubview:_ramBar];

    _diskBar = [[MiransasProgressBar alloc] initWithFrame:NSZeroRect];
    _diskBar.barLabel = @"Disk";
    _diskBar.valueText = @"--";
    [self addSubview:_diskBar];

    _battery = [[MiransasBatteryWidget alloc] initWithFrame:NSZeroRect];
    [self addSubview:_battery];

    _thermal = [[MiransasThermalWidget alloc] initWithFrame:NSZeroRect];
    [self addSubview:_thermal];

    return self;
}

- (void)layout {
    [super layout];
    NSRect b = self.bounds;
    CGFloat pad = 24.0;
    CGFloat gaugeSize = MIN(180.0, b.size.height * 0.42);
    CGFloat barRowH = 30.0;
    CGFloat barGap = 6.0;
    CGFloat widgetH = 100.0;
    CGFloat sectionGap = 18.0;

    _gauge.frame = NSMakeRect((b.size.width - gaugeSize) / 2.0,
                              b.size.height - pad - gaugeSize,
                              gaugeSize, gaugeSize);

    CGFloat barsTop = b.size.height - pad - gaugeSize - sectionGap;
    CGFloat barsWidth = MIN(440.0, b.size.width - 2.0 * pad);
    CGFloat barsX = (b.size.width - barsWidth) / 2.0;
    _cpuBar.frame  = NSMakeRect(barsX, barsTop - barRowH,                          barsWidth, barRowH);
    _ramBar.frame  = NSMakeRect(barsX, barsTop - 2.0 * barRowH - barGap,           barsWidth, barRowH);
    _diskBar.frame = NSMakeRect(barsX, barsTop - 3.0 * barRowH - 2.0 * barGap,     barsWidth, barRowH);

    CGFloat widgetGap = 16.0;
    CGFloat widgetW = (b.size.width - 2.0 * pad - widgetGap) / 2.0;
    _battery.frame = NSMakeRect(pad,                       pad, widgetW, widgetH);
    _thermal.frame = NSMakeRect(pad + widgetW + widgetGap, pad, widgetW, widgetH);
}

- (void)updateWithSnapshot:(const agent_snapshot_t *)snapshot {
    if (!snapshot) return;

    _gauge.score = snapshot->health_score;

    double cpu = snapshot->system.cpu_usage;
    if (cpu < 0.0) cpu = 0.0;
    _cpuBar.valueText = [NSString stringWithFormat:@"%.1f %%", cpu];
    _cpuBar.fraction  = MIN(MAX(cpu / 100.0, 0.0), 1.0);

    uint64_t total = snapshot->system.total_ram;
    uint64_t freev = snapshot->system.free_ram;
    uint64_t used  = (total > freev) ? (total - freev) : 0;
    double ramFraction = (total > 0) ? ((double)used / (double)total) : 0.0;
    _ramBar.valueText = [NSString stringWithFormat:@"%llu / %llu MB",
                         (unsigned long long)used, (unsigned long long)total];
    _ramBar.fraction  = ramFraction;

    struct statfs s;
    if (statfs("/", &s) == 0) {
        uint64_t bsize = (uint64_t)s.f_bsize;
        uint64_t totalBytes = (uint64_t)s.f_blocks * bsize;
        uint64_t freeBytes  = (uint64_t)s.f_bavail * bsize;
        uint64_t usedBytes  = (totalBytes > freeBytes) ? (totalBytes - freeBytes) : 0;
        double diskFraction = (totalBytes > 0)
                              ? ((double)usedBytes / (double)totalBytes) : 0.0;
        double gibUsed  = (double)usedBytes  / (1024.0 * 1024.0 * 1024.0);
        double gibTotal = (double)totalBytes / (1024.0 * 1024.0 * 1024.0);
        _diskBar.valueText = [NSString stringWithFormat:@"%.1f / %.0f GB",
                              gibUsed, gibTotal];
        _diskBar.fraction  = diskFraction;
    } else {
        _diskBar.valueText = @"unavailable";
        _diskBar.fraction  = 0.0;
    }

    [_battery refresh];
    [_thermal refresh];
}

@end
