#import "tab_storage.h"

#include <sys/mount.h>
#include <sys/param.h>

#pragma mark - Helpers

static uint64_t top_level_size(NSString *path) {
    if (!path) return 0;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *err = nil;
    NSArray<NSString *> *contents = [fm contentsOfDirectoryAtPath:path error:&err];
    if (!contents) return 0;
    uint64_t total = 0;
    for (NSString *name in contents) {
        if ([name hasPrefix:@"."]) continue;
        NSString *itemPath = [path stringByAppendingPathComponent:name];
        NSDictionary *attrs = [fm attributesOfItemAtPath:itemPath error:NULL];
        if (attrs) {
            total += [[attrs objectForKey:NSFileSize] unsignedLongLongValue];
        }
    }
    return total;
}

static NSString *home_subpath(NSString *sub) {
    NSString *home = NSHomeDirectory();
    return [home stringByAppendingPathComponent:sub];
}

static NSString *format_bytes(uint64_t bytes) {
    return [NSByteCountFormatter stringFromByteCount:(long long)bytes
                                          countStyle:NSByteCountFormatterCountStyleFile];
}

#pragma mark - Category model

@interface MiransasStorageCategory : NSObject
@property(nonatomic, copy)   NSString *name;
@property(nonatomic, copy)   NSString *symbolName;
@property(nonatomic, strong) NSColor *color;
@property(nonatomic, assign) uint64_t bytes;
@property(nonatomic, assign) double fraction;  // of total disk
@end

@implementation MiransasStorageCategory
- (void)dealloc {
    [_name release];
    [_symbolName release];
    [_color release];
    [super dealloc];
}
@end

#pragma mark - Stacked bar

@interface MiransasStackedBar : NSView
- (void)setCategories:(NSArray<MiransasStorageCategory *> *)categories
            freeBytes:(uint64_t)freeBytes
           totalBytes:(uint64_t)totalBytes;
@end

@implementation MiransasStackedBar {
    NSArray<MiransasStorageCategory *> *_categories;
    uint64_t _freeBytes;
    uint64_t _totalBytes;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (!self) return nil;
    self.wantsLayer = YES;
    self.layer.cornerRadius = 7.0;
    self.layer.masksToBounds = YES;
    self.layer.backgroundColor = [[[NSColor labelColor] colorWithAlphaComponent:0.08] CGColor];
    return self;
}

- (void)dealloc {
    [_categories release];
    [super dealloc];
}

- (void)setCategories:(NSArray<MiransasStorageCategory *> *)categories
            freeBytes:(uint64_t)freeBytes
           totalBytes:(uint64_t)totalBytes {
    [_categories release];
    _categories = [categories retain];
    _freeBytes = freeBytes;
    _totalBytes = totalBytes;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    if (_totalBytes == 0) return;
    NSRect b = self.bounds;
    CGFloat x = 0.0;
    for (MiransasStorageCategory *c in _categories) {
        CGFloat w = (CGFloat)((double)c.bytes / (double)_totalBytes) * b.size.width;
        if (w <= 0.0) continue;
        NSRect r = NSMakeRect(x, 0.0, w, b.size.height);
        [c.color setFill];
        NSRectFill(r);
        x += w;
    }
}

@end

#pragma mark - Row

@interface MiransasStorageRow : NSView
- (instancetype)initWithCategory:(MiransasStorageCategory *)category
                      totalBytes:(uint64_t)totalBytes;
@end

@implementation MiransasStorageRow {
    NSImageView *_icon;
    NSTextField *_name;
    NSTextField *_size;
    NSTextField *_percent;
}

- (instancetype)initWithCategory:(MiransasStorageCategory *)category
                      totalBytes:(uint64_t)totalBytes {
    self = [super initWithFrame:NSZeroRect];
    if (!self) return nil;

    _icon = [[NSImageView alloc] init];
    [_icon setImageScaling:NSImageScaleProportionallyUpOrDown];
    if (@available(macOS 11.0, *)) {
        NSImage *img = [NSImage imageWithSystemSymbolName:category.symbolName
                                  accessibilityDescription:nil];
        _icon.image = img;
        _icon.contentTintColor = category.color;
    }
    [self addSubview:_icon];

    _name = [[NSTextField alloc] init];
    [_name setBezeled:NO];
    [_name setDrawsBackground:NO];
    [_name setEditable:NO];
    [_name setSelectable:NO];
    [_name setStringValue:category.name];
    [_name setFont:[NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium]];
    [_name setTextColor:[NSColor labelColor]];
    [self addSubview:_name];

    _size = [[NSTextField alloc] init];
    [_size setBezeled:NO];
    [_size setDrawsBackground:NO];
    [_size setEditable:NO];
    [_size setSelectable:NO];
    [_size setAlignment:NSTextAlignmentRight];
    [_size setStringValue:format_bytes(category.bytes)];
    [_size setFont:[NSFont monospacedDigitSystemFontOfSize:12.0
                                                    weight:NSFontWeightRegular]];
    [_size setTextColor:[NSColor labelColor]];
    [self addSubview:_size];

    _percent = [[NSTextField alloc] init];
    [_percent setBezeled:NO];
    [_percent setDrawsBackground:NO];
    [_percent setEditable:NO];
    [_percent setSelectable:NO];
    [_percent setAlignment:NSTextAlignmentRight];
    double pct = (totalBytes > 0)
                 ? ((double)category.bytes / (double)totalBytes * 100.0) : 0.0;
    [_percent setStringValue:[NSString stringWithFormat:@"%.1f %%", pct]];
    [_percent setFont:[NSFont monospacedDigitSystemFontOfSize:11.0
                                                       weight:NSFontWeightRegular]];
    [_percent setTextColor:[NSColor secondaryLabelColor]];
    [self addSubview:_percent];

    return self;
}

- (void)layout {
    [super layout];
    NSRect b = self.bounds;
    CGFloat iconW = 22.0;
    CGFloat iconGap = 10.0;
    CGFloat sizeW = 90.0;
    CGFloat pctW = 60.0;
    CGFloat gap = 10.0;

    CGFloat midY = b.size.height / 2.0;
    _icon.frame   = NSMakeRect(0.0, midY - iconW / 2.0, iconW, iconW);

    CGFloat nameX = iconW + iconGap;
    CGFloat tailX = b.size.width - pctW - gap - sizeW;
    if (tailX < nameX + 40.0) tailX = nameX + 40.0;

    _name.frame    = NSMakeRect(nameX, midY - 9.0, tailX - nameX, 18.0);
    _size.frame    = NSMakeRect(tailX, midY - 8.0, sizeW, 16.0);
    _percent.frame = NSMakeRect(tailX + sizeW + gap, midY - 7.0, pctW, 14.0);
}

@end

#pragma mark - Tab

@interface MiransasStorageTab ()
@end

@implementation MiransasStorageTab {
    NSTextField *_titleField;
    NSTextField *_summaryField;
    NSTextField *_noteField;
    MiransasStackedBar *_bar;
    NSMutableArray<MiransasStorageRow *> *_rows;
    NSView *_listContainer;

    time_t _lastComputed;
    uint64_t _cachedTotal;
    uint64_t _cachedFree;
    NSArray<MiransasStorageCategory *> *_cachedCategories;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (!self) return nil;
    self.wantsLayer = YES;
    self.layer.backgroundColor = [[NSColor windowBackgroundColor] CGColor];

    _rows = [[NSMutableArray alloc] init];

    _titleField = [[NSTextField alloc] init];
    [_titleField setBezeled:NO];
    [_titleField setDrawsBackground:NO];
    [_titleField setEditable:NO];
    [_titleField setSelectable:NO];
    [_titleField setStringValue:@"STORAGE"];
    [_titleField setFont:[NSFont systemFontOfSize:12.0 weight:NSFontWeightSemibold]];
    [_titleField setTextColor:[NSColor systemOrangeColor]];
    [self addSubview:_titleField];

    _summaryField = [[NSTextField alloc] init];
    [_summaryField setBezeled:NO];
    [_summaryField setDrawsBackground:NO];
    [_summaryField setEditable:NO];
    [_summaryField setSelectable:NO];
    [_summaryField setStringValue:@""];
    [_summaryField setFont:[NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular]];
    [_summaryField setTextColor:[NSColor secondaryLabelColor]];
    [self addSubview:_summaryField];

    _bar = [[MiransasStackedBar alloc] initWithFrame:NSZeroRect];
    [self addSubview:_bar];

    _noteField = [[NSTextField alloc] init];
    [_noteField setBezeled:NO];
    [_noteField setDrawsBackground:NO];
    [_noteField setEditable:NO];
    [_noteField setSelectable:NO];
    [_noteField setStringValue:
        @"Sizes are top-level only (no recursive enumeration). "
        @"Bundles and nested subfolders roll up into Other."];
    [_noteField setFont:[NSFont systemFontOfSize:10.0 weight:NSFontWeightRegular]];
    [_noteField setTextColor:[NSColor tertiaryLabelColor]];
    [_noteField setLineBreakMode:NSLineBreakByWordWrapping];
    [[_noteField cell] setWraps:YES];
    [self addSubview:_noteField];

    _listContainer = [[NSView alloc] initWithFrame:NSZeroRect];
    [self addSubview:_listContainer];

    return self;
}

- (void)dealloc {
    [_cachedCategories release];
    [_rows release];
    [super dealloc];
}

- (void)layout {
    [super layout];
    NSRect b = self.bounds;
    CGFloat pad = 24.0;
    CGFloat innerW = b.size.width - 2.0 * pad;

    CGFloat titleH = 16.0;
    CGFloat barH = 22.0;
    CGFloat summaryH = 16.0;
    CGFloat noteH = 28.0;
    CGFloat rowH = 30.0;
    CGFloat rowGap = 2.0;

    CGFloat y = b.size.height - pad;

    y -= titleH;
    _titleField.frame = NSMakeRect(pad, y, innerW, titleH);

    y -= 10.0 + barH;
    _bar.frame = NSMakeRect(pad, y, innerW, barH);

    y -= 6.0 + summaryH;
    _summaryField.frame = NSMakeRect(pad, y, innerW, summaryH);

    y -= 4.0 + noteH;
    _noteField.frame = NSMakeRect(pad, y, innerW, noteH);

    y -= 12.0;
    _listContainer.frame = NSMakeRect(pad, pad, innerW, y - pad);

    NSRect lb = _listContainer.bounds;
    CGFloat ry = lb.size.height;
    for (MiransasStorageRow *row in _rows) {
        ry -= rowH;
        row.frame = NSMakeRect(0.0, ry, lb.size.width, rowH);
        ry -= rowGap;
    }
}

#pragma mark - Data

- (BOOL)cacheFresh {
    if (_lastComputed == 0) return NO;
    return (time(NULL) - _lastComputed) < 60;
}

- (void)recompute {
    struct statfs s;
    uint64_t total = 0, freev = 0;
    if (statfs("/", &s) == 0) {
        uint64_t bsize = (uint64_t)s.f_bsize;
        total = (uint64_t)s.f_blocks * bsize;
        freev = (uint64_t)s.f_bavail * bsize;
    }
    uint64_t used = (total > freev) ? (total - freev) : 0;

    uint64_t appsB     = top_level_size(@"/Applications");
    uint64_t docsB     = top_level_size(home_subpath(@"Documents"));
    uint64_t cachesB   = top_level_size(home_subpath(@"Library/Caches"));
    uint64_t dlB       = top_level_size(home_subpath(@"Downloads"));
    uint64_t picsB     = top_level_size(home_subpath(@"Pictures"));
    uint64_t accounted = appsB + docsB + cachesB + dlB + picsB;
    uint64_t otherB    = (used > accounted) ? (used - accounted) : 0;

    NSMutableArray<MiransasStorageCategory *> *cats = [NSMutableArray array];

    void (^add)(NSString *, NSString *, NSColor *, uint64_t) =
        ^(NSString *name, NSString *symbol, NSColor *color, uint64_t bytes) {
        MiransasStorageCategory *c = [[MiransasStorageCategory alloc] init];
        c.name = name;
        c.symbolName = symbol;
        c.color = color;
        c.bytes = bytes;
        c.fraction = (total > 0) ? ((double)bytes / (double)total) : 0.0;
        [cats addObject:c];
        [c release];
    };

    add(@"Applications",      @"app.fill",                [NSColor systemBlueColor],   appsB);
    add(@"Documents",         @"doc.fill",                [NSColor systemPurpleColor], docsB);
    add(@"Caches",            @"internaldrive.fill",      [NSColor systemTealColor],   cachesB);
    add(@"Downloads",         @"arrow.down.circle.fill",  [NSColor systemIndigoColor], dlB);
    add(@"Photos",            @"photo.fill",              [NSColor systemPinkColor],   picsB);
    add(@"Other (incl. System)", @"questionmark.folder",  [NSColor systemGrayColor],   otherB);

    [_cachedCategories release];
    _cachedCategories = [cats retain];
    _cachedTotal = total;
    _cachedFree = freev;
    _lastComputed = time(NULL);
}

- (void)rebuildRows {
    for (MiransasStorageRow *r in _rows) {
        [r removeFromSuperview];
    }
    [_rows removeAllObjects];

    for (MiransasStorageCategory *c in _cachedCategories) {
        MiransasStorageRow *row = [[MiransasStorageRow alloc] initWithCategory:c
                                                                    totalBytes:_cachedTotal];
        [_listContainer addSubview:row];
        [_rows addObject:row];
        [row release];
    }

    [_bar setCategories:_cachedCategories
              freeBytes:_cachedFree
             totalBytes:_cachedTotal];

    [_summaryField setStringValue:[NSString stringWithFormat:@"%@ used of %@   ·   %@ free",
                                   format_bytes(_cachedTotal - _cachedFree),
                                   format_bytes(_cachedTotal),
                                   format_bytes(_cachedFree)]];

    [self setNeedsLayout:YES];
}

- (void)updateWithSnapshot:(const agent_snapshot_t *)snapshot {
    (void)snapshot;
    if (![self cacheFresh]) {
        [self recompute];
        [self rebuildRows];
    }
}

@end
