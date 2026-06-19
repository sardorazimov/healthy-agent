#import "tab_storage.h"
#import "cleanup.h"
#import "ui_helpers.h"

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
    NSColor *separator = [[NSColor windowBackgroundColor]
                          colorWithAlphaComponent:0.55];
    BOOL drewPrevious = NO;
    for (MiransasStorageCategory *c in _categories) {
        CGFloat w = (CGFloat)((double)c.bytes / (double)_totalBytes) * b.size.width;
        if (w <= 0.0) continue;
        // 1px separator before each segment after the first non-empty one,
        // for visual clarity between adjacent fills.
        if (drewPrevious) {
            [separator setFill];
            NSRectFill(NSMakeRect(x, 0.0, 1.0, b.size.height));
            x += 1.0;
            w -= 1.0;
            if (w <= 0.0) continue;
        }
        NSRect r = NSMakeRect(x, 0.0, w, b.size.height);
        [c.color setFill];
        NSRectFill(r);
        x += w;
        drewPrevious = YES;
    }
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    m_set_layer_bg(self.layer,
        [[NSColor labelColor] colorWithAlphaComponent:0.08], self);
    [self setNeedsDisplay:YES];
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
    [_size setFont:[NSFont monospacedDigitSystemFontOfSize:13.0
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

#pragma mark - Flipped helper view

@interface MiransasStorageFlippedView : NSView
@end
@implementation MiransasStorageFlippedView
- (BOOL)isFlipped { return YES; }
@end

#pragma mark - Tab

@interface MiransasStorageTab ()
@end

@implementation MiransasStorageTab {
    NSScrollView *_scrollView;
    MiransasStorageFlippedView *_content;

    NSTextField *_titleField;
    NSTextField *_summaryField;
    NSTextField *_noteField;
    MiransasStackedBar *_bar;
    NSMutableArray<MiransasStorageRow *> *_rows;
    MiransasStorageFlippedView *_listContainer;

    NSTextField *_cleanupHeader;
    MiransasCleanupCard *_cachesCard;
    MiransasCleanupCard *_downloadsCard;
    MiransasCleanupCard *_largeFilesCard;
    MiransasCleanupCard *_staleArtifactsCard;

    time_t _lastComputed;
    uint64_t _cachedTotal;
    uint64_t _cachedFree;
    NSArray<MiransasStorageCategory *> *_cachedCategories;

    BOOL _cachesScanInFlight;
    BOOL _cachesScanLoaded;
    uint64_t _cachesTotalBytes;
    NSUInteger _cachesEntryCount;

    BOOL _downloadsScanInFlight;
    BOOL _downloadsScanLoaded;
    uint64_t _downloadsTotalBytes;
    NSUInteger _downloadsEntryCount;

    BOOL _largeFilesScanInFlight;
    BOOL _largeFilesScanLoaded;
    uint64_t _largeFilesTotalBytes;
    NSUInteger _largeFilesEntryCount;

    BOOL _staleArtifactsScanInFlight;
    BOOL _staleArtifactsScanLoaded;
    uint64_t _staleArtifactsTotalBytes;
    NSUInteger _staleArtifactsEntryCount;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (!self) return nil;
    self.wantsLayer = YES;
    self.layer.backgroundColor = [[NSColor windowBackgroundColor] CGColor];

    _rows = [[NSMutableArray alloc] init];

    _scrollView = [[NSScrollView alloc] initWithFrame:self.bounds];
    [_scrollView setBorderType:NSNoBorder];
    [_scrollView setDrawsBackground:NO];
    [_scrollView setHasVerticalScroller:YES];
    [_scrollView setHasHorizontalScroller:NO];
    [_scrollView setAutohidesScrollers:YES];
    [_scrollView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [self addSubview:_scrollView];

    _content = [[MiransasStorageFlippedView alloc] initWithFrame:NSMakeRect(
        0.0, 0.0, frameRect.size.width, frameRect.size.height)];
    [_content setAutoresizingMask:NSViewWidthSizable];
    [_scrollView setDocumentView:_content];

    _titleField = [[NSTextField alloc] init];
    [_titleField setBezeled:NO];
    [_titleField setDrawsBackground:NO];
    [_titleField setEditable:NO];
    [_titleField setSelectable:NO];
    [_titleField setStringValue:@"STORAGE"];
    [_titleField setFont:[NSFont systemFontOfSize:11.0 weight:NSFontWeightSemibold]];
    [_titleField setTextColor:[NSColor systemOrangeColor]];
    [_content addSubview:_titleField];

    _summaryField = [[NSTextField alloc] init];
    [_summaryField setBezeled:NO];
    [_summaryField setDrawsBackground:NO];
    [_summaryField setEditable:NO];
    [_summaryField setSelectable:NO];
    [_summaryField setStringValue:@""];
    [_summaryField setFont:[NSFont systemFontOfSize:13.0 weight:NSFontWeightRegular]];
    [_summaryField setTextColor:[NSColor secondaryLabelColor]];
    [_content addSubview:_summaryField];

    _bar = [[MiransasStackedBar alloc] initWithFrame:NSZeroRect];
    [_content addSubview:_bar];

    _noteField = [[NSTextField alloc] init];
    [_noteField setBezeled:NO];
    [_noteField setDrawsBackground:NO];
    [_noteField setEditable:NO];
    [_noteField setSelectable:NO];
    [_noteField setStringValue:
        @"Top-level sizes only (no recursive scan). System is derived from "
        @"system roots; Other is the unaccounted remainder. Refreshed every 60s."];
    [_noteField setFont:[NSFont systemFontOfSize:11.0 weight:NSFontWeightRegular]];
    [_noteField setTextColor:[NSColor tertiaryLabelColor]];
    [_noteField setLineBreakMode:NSLineBreakByWordWrapping];
    [[_noteField cell] setWraps:YES];
    [_content addSubview:_noteField];

    _listContainer = [[MiransasStorageFlippedView alloc] initWithFrame:NSZeroRect];
    [_content addSubview:_listContainer];

    _cleanupHeader = [[NSTextField alloc] init];
    [_cleanupHeader setBezeled:NO];
    [_cleanupHeader setDrawsBackground:NO];
    [_cleanupHeader setEditable:NO];
    [_cleanupHeader setSelectable:NO];
    [_cleanupHeader setStringValue:@"CLEANUP"];
    [_cleanupHeader setFont:[NSFont systemFontOfSize:11.0 weight:NSFontWeightSemibold]];
    [_cleanupHeader setTextColor:[NSColor systemOrangeColor]];
    [_content addSubview:_cleanupHeader];

    _cachesCard = [[MiransasCleanupCard alloc]
        initWithTitle:@"User Caches"
               symbol:@"externaldrive.badge.minus"
          description:@"Application caches in ~/Library/Caches/ (safe to delete)"
          actionTitle:@"Review & Clean →"];
    [_cachesCard setStatsText:@"Scanning…"];
    [_cachesCard setActionEnabled:NO];
    [_cachesCard setActionPrimary:YES];
    __unsafe_unretained MiransasStorageTab *weakSelf = self;
    _cachesCard.onAction = ^{ [weakSelf openCachesReview]; };
    [_content addSubview:_cachesCard];

    _downloadsCard = [[MiransasCleanupCard alloc]
        initWithTitle:@"Downloads folder"
               symbol:@"tray.and.arrow.down.fill"
          description:@"Files in ~/Downloads/"
          actionTitle:@"Review & Clean →"];
    [_downloadsCard setStatsText:@"Scanning…"];
    [_downloadsCard setActionEnabled:NO];
    [_downloadsCard setActionPrimary:YES];
    _downloadsCard.onAction = ^{ [weakSelf openDownloadsReview]; };
    [_content addSubview:_downloadsCard];

    _largeFilesCard = [[MiransasCleanupCard alloc]
        initWithTitle:@"Large Files"
               symbol:@"doc.text.magnifyingglass"
          description:@"Files over 100 MB anywhere in ~/"
          actionTitle:@"Scan now"];
    [_largeFilesCard setStatsText:@"Not scanned yet"];
    [_largeFilesCard setActionEnabled:YES];
    [_largeFilesCard setActionPrimary:NO];
    _largeFilesCard.onAction = ^{ [weakSelf largeFilesAction]; };
    [_content addSubview:_largeFilesCard];

    _staleArtifactsCard = [[MiransasCleanupCard alloc]
        initWithTitle:@"Stale Project Artifacts"
               symbol:@"archivebox.fill"
          description:@"node_modules, target/, .build/, dist/, build/ folders not modified in 30+ days"
          actionTitle:@"Scan now"];
    [_staleArtifactsCard setStatsText:@"Not scanned yet"];
    [_staleArtifactsCard setActionEnabled:YES];
    [_staleArtifactsCard setActionPrimary:NO];
    _staleArtifactsCard.onAction = ^{ [weakSelf staleArtifactsAction]; };
    [_content addSubview:_staleArtifactsCard];

    [self kickoffCachesScan];
    [self kickoffDownloadsScan];

    return self;
}

- (void)dealloc {
    [_cachedCategories release];
    [_rows release];
    [_scrollView release];
    [_content release];
    [_listContainer release];
    [_cachesCard release];
    [_downloadsCard release];
    [_largeFilesCard release];
    [_staleArtifactsCard release];
    [super dealloc];
}

#pragma mark - Layout

- (void)layout {
    [super layout];
    _scrollView.frame = self.bounds;
    CGFloat width = _scrollView.contentSize.width;
    CGFloat h = [self layoutContentForWidth:width];
    NSRect cf = _content.frame;
    cf.size.width = width;
    cf.size.height = h;
    _content.frame = cf;
}

- (CGFloat)layoutContentForWidth:(CGFloat)width {
    CGFloat pad = 24.0;
    CGFloat innerW = width - 2.0 * pad;
    if (innerW < 100.0) innerW = 100.0;

    CGFloat titleH = 16.0;
    CGFloat barH = 22.0;
    CGFloat summaryH = 16.0;
    CGFloat noteH = 32.0;
    CGFloat rowH = 30.0;
    CGFloat rowGap = 2.0;
    CGFloat headerH = 16.0;
    CGFloat cardH = 96.0;

    CGFloat y = pad;

    _titleField.frame = NSMakeRect(pad, y, innerW, titleH);
    y += titleH + 10.0;

    _bar.frame = NSMakeRect(pad, y, innerW, barH);
    y += barH + 6.0;

    _summaryField.frame = NSMakeRect(pad, y, innerW, summaryH);
    y += summaryH + 4.0;

    _noteField.frame = NSMakeRect(pad, y, innerW, noteH);
    y += noteH + 12.0;

    NSUInteger n = _rows.count;
    CGFloat listH = (n == 0) ? 0.0
                              : (n * rowH + (n - 1) * rowGap);
    _listContainer.frame = NSMakeRect(pad, y, innerW, listH);
    CGFloat ry = 0.0;
    for (MiransasStorageRow *row in _rows) {
        row.frame = NSMakeRect(0.0, ry, innerW, rowH);
        ry += rowH + rowGap;
    }
    y += listH + 32.0;

    _cleanupHeader.frame = NSMakeRect(pad, y, innerW, headerH);
    y += headerH + 8.0;

    _cachesCard.frame = NSMakeRect(pad, y, innerW, cardH);
    y += cardH + 10.0;

    _downloadsCard.frame = NSMakeRect(pad, y, innerW, cardH);
    y += cardH + 10.0;

    _largeFilesCard.frame = NSMakeRect(pad, y, innerW, cardH);
    y += cardH + 10.0;

    _staleArtifactsCard.frame = NSMakeRect(pad, y, innerW, cardH);
    y += cardH + pad;

    return y;
}

#pragma mark - Storage breakdown

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

    uint64_t appsB    = top_level_size(@"/Applications");
    uint64_t docsB    = top_level_size(home_subpath(@"Documents"));
    uint64_t cachesB  = top_level_size(home_subpath(@"Library/Caches"));
    uint64_t dlB      = top_level_size(home_subpath(@"Downloads"));
    uint64_t picsB    = top_level_size(home_subpath(@"Pictures"));

    uint64_t systemB  = top_level_size(@"/System")
                      + top_level_size(@"/Library")
                      + top_level_size(@"/private")
                      + top_level_size(@"/usr");

    uint64_t namedB   = appsB + docsB + cachesB + dlB + picsB + systemB;
    uint64_t otherB   = (used > namedB) ? (used - namedB) : 0;

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

    add(@"Applications", @"app.fill",                  [NSColor systemBlueColor],   appsB);
    add(@"Documents",    @"doc.fill",                  [NSColor systemPinkColor],   docsB);
    add(@"Caches",       @"internaldrive.fill",        [NSColor systemTealColor],   cachesB);
    add(@"Downloads",    @"arrow.down.circle.fill",    [NSColor systemPurpleColor], dlB);
    add(@"Photos",       @"photo.fill",                [NSColor systemRedColor],    picsB);
    add(@"System",       @"gearshape.2.fill",          [NSColor systemYellowColor], systemB);
    add(@"Other",        @"questionmark.folder.fill",  [NSColor systemGrayColor],   otherB);

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

#pragma mark - Cleanup: caches

- (void)kickoffCachesScan {
    if (_cachesScanInFlight) return;
    _cachesScanInFlight = YES;
    [_cachesCard setStatsText:@"Scanning…"];
    [_cachesCard setActionEnabled:NO];

    __unsafe_unretained MiransasStorageTab *weakSelf = self;
    [MiransasCleanup loadCacheEntriesWithCompletion:^(NSArray<MiransasCleanupEntry *> *entries) {
        [weakSelf onCachesScanLoaded:entries];
    }];
}

- (void)onCachesScanLoaded:(NSArray<MiransasCleanupEntry *> *)entries {
    _cachesScanInFlight = NO;
    _cachesScanLoaded = YES;
    uint64_t total = 0;
    for (MiransasCleanupEntry *e in entries) total += e.bytes;
    _cachesTotalBytes = total;
    _cachesEntryCount = entries.count;
    [self refreshCachesStats];
}

- (void)refreshCachesStats {
    if (!_cachesScanLoaded) {
        [_cachesCard setStatsText:@"Scanning…"];
        [_cachesCard setActionEnabled:NO];
        return;
    }
    if (_cachesEntryCount == 0) {
        [_cachesCard setStatsText:@"Nothing to clean"];
        [_cachesCard setActionEnabled:NO];
        return;
    }
    [_cachesCard setStatsText:
        [NSString stringWithFormat:@"%@ across %lu folder%s",
                                   [MiransasCleanup formatBytes:_cachesTotalBytes],
                                   (unsigned long)_cachesEntryCount,
                                   _cachesEntryCount == 1 ? "" : "s"]];
    [_cachesCard setActionEnabled:YES];
}

- (void)openCachesReview {
    NSArray<MiransasCleanupEntry *> *entries = [MiransasCleanup cachedCacheEntries];
    if (!entries) {
        [_cachesCard setStatsText:@"Scanning… please retry shortly"];
        [self kickoffCachesScan];
        return;
    }
    for (MiransasCleanupEntry *e in entries) e.selected = NO;

    NSWindow *parent = self.window;
    if (!parent) return;

    MiransasCleanupSheet *sheet = [[MiransasCleanupSheet alloc]
        initWithTitle:@"User Caches"
             subtitle:@"Select cache folders to move to Trash. Items will be moved to the Trash, not permanently deleted."
              entries:entries
         extraWarning:nil];

    __block MiransasCleanupSheet *holder = sheet;
    __unsafe_unretained MiransasStorageTab *weakSelf = self;
    [sheet beginSheetForWindow:parent
                    completion:^(BOOL didTrash, NSUInteger count, uint64_t bytes) {
        if (didTrash) {
            [MiransasCleanup invalidateCacheEntriesCache];
            [weakSelf kickoffCachesScan];
            (void)count; (void)bytes;
        }
        [holder release];
        holder = nil;
    }];
}

#pragma mark - Cleanup: downloads

- (void)kickoffDownloadsScan {
    if (_downloadsScanInFlight) return;
    _downloadsScanInFlight = YES;
    [_downloadsCard setStatsText:@"Scanning…"];
    [_downloadsCard setActionEnabled:NO];

    __unsafe_unretained MiransasStorageTab *weakSelf = self;
    [MiransasCleanup loadDownloadsEntriesWithCompletion:^(NSArray<MiransasCleanupEntry *> *entries) {
        [weakSelf onDownloadsScanLoaded:entries];
    }];
}

- (void)onDownloadsScanLoaded:(NSArray<MiransasCleanupEntry *> *)entries {
    _downloadsScanInFlight = NO;
    _downloadsScanLoaded = YES;
    uint64_t total = 0;
    for (MiransasCleanupEntry *e in entries) total += e.bytes;
    _downloadsTotalBytes = total;
    _downloadsEntryCount = entries.count;
    [self refreshDownloadsStats];
}

- (void)refreshDownloadsStats {
    if (!_downloadsScanLoaded) {
        [_downloadsCard setStatsText:@"Scanning…"];
        [_downloadsCard setEmptyStateSymbol:nil];
        [_downloadsCard setActionEnabled:NO];
        [_downloadsCard setActionHidden:NO];
        return;
    }
    if (_downloadsEntryCount == 0) {
        [_downloadsCard setStatsText:@"Downloads folder is empty"];
        [_downloadsCard setEmptyStateSymbol:@"tray"];
        [_downloadsCard setActionEnabled:NO];
        [_downloadsCard setActionHidden:YES];
        return;
    }
    [_downloadsCard setStatsText:
        [NSString stringWithFormat:@"%@ across %lu file%s",
                                   [MiransasCleanup formatBytes:_downloadsTotalBytes],
                                   (unsigned long)_downloadsEntryCount,
                                   _downloadsEntryCount == 1 ? "" : "s"]];
    [_downloadsCard setEmptyStateSymbol:nil];
    [_downloadsCard setActionEnabled:YES];
    [_downloadsCard setActionHidden:NO];
}

- (void)openDownloadsReview {
    NSArray<MiransasCleanupEntry *> *entries = [MiransasCleanup cachedDownloadsEntries];
    if (!entries) {
        [_downloadsCard setStatsText:@"Scanning… please retry shortly"];
        [self kickoffDownloadsScan];
        return;
    }
    for (MiransasCleanupEntry *e in entries) e.selected = NO;

    NSWindow *parent = self.window;
    if (!parent) return;

    MiransasCleanupSheet *sheet = [[MiransasCleanupSheet alloc]
        initWithTitle:@"Downloads"
             subtitle:@"Select files to move to Trash. Items will be moved to the Trash, not permanently deleted."
              entries:entries
         extraWarning:nil];

    __block MiransasCleanupSheet *holder = sheet;
    __unsafe_unretained MiransasStorageTab *weakSelf = self;
    [sheet beginSheetForWindow:parent
                    completion:^(BOOL didTrash, NSUInteger count, uint64_t bytes) {
        if (didTrash) {
            [MiransasCleanup invalidateDownloadsEntriesCache];
            [weakSelf kickoffDownloadsScan];
            (void)count; (void)bytes;
        }
        [holder release];
        holder = nil;
    }];
}

#pragma mark - Cleanup: large files

- (void)largeFilesAction {
    if (_largeFilesScanInFlight) return;
    if (_largeFilesScanLoaded) {
        [self openLargeFilesReview];
    } else {
        [self kickoffLargeFilesScan];
    }
}

- (void)kickoffLargeFilesScan {
    if (_largeFilesScanInFlight) return;
    _largeFilesScanInFlight = YES;
    [_largeFilesCard setStatsText:@"Scanning ~/ for files over 100 MB…"];
    [_largeFilesCard setActionEnabled:NO];
    [_largeFilesCard setActionHidden:NO];
    [_largeFilesCard setScanning:YES];

    __unsafe_unretained MiransasStorageTab *weakSelf = self;
    [MiransasCleanup loadLargeFilesEntriesWithCompletion:^(NSArray<MiransasCleanupEntry *> *entries) {
        [weakSelf onLargeFilesScanLoaded:entries];
    }];
}

- (void)onLargeFilesScanLoaded:(NSArray<MiransasCleanupEntry *> *)entries {
    _largeFilesScanInFlight = NO;
    _largeFilesScanLoaded = YES;
    uint64_t total = 0;
    for (MiransasCleanupEntry *e in entries) total += e.bytes;
    _largeFilesTotalBytes = total;
    _largeFilesEntryCount = entries.count;
    [_largeFilesCard setScanning:NO];
    [self refreshLargeFilesStats];
}

- (void)refreshLargeFilesStats {
    if (!_largeFilesScanLoaded) {
        [_largeFilesCard setStatsText:@"Not scanned yet"];
        [_largeFilesCard setEmptyStateSymbol:@"magnifyingglass.circle"];
        [_largeFilesCard setActionTitle:@"Scan now"];
        [_largeFilesCard setActionPrimary:NO];
        [_largeFilesCard setActionEnabled:YES];
        [_largeFilesCard setActionHidden:NO];
        return;
    }
    [_largeFilesCard setActionTitle:@"Review & Clean →"];
    [_largeFilesCard setActionPrimary:YES];
    if (_largeFilesEntryCount == 0) {
        [_largeFilesCard setStatsText:@"No files over 100 MB found"];
        [_largeFilesCard setEmptyStateSymbol:@"magnifyingglass.circle"];
        [_largeFilesCard setActionEnabled:NO];
        [_largeFilesCard setActionHidden:YES];
        return;
    }
    [_largeFilesCard setStatsText:
        [NSString stringWithFormat:@"%@ across %lu file%s",
                                   [MiransasCleanup formatBytes:_largeFilesTotalBytes],
                                   (unsigned long)_largeFilesEntryCount,
                                   _largeFilesEntryCount == 1 ? "" : "s"]];
    [_largeFilesCard setEmptyStateSymbol:nil];
    [_largeFilesCard setActionEnabled:YES];
    [_largeFilesCard setActionHidden:NO];
}

- (void)openLargeFilesReview {
    NSArray<MiransasCleanupEntry *> *entries = [MiransasCleanup cachedLargeFilesEntries];
    if (!entries) {
        [self kickoffLargeFilesScan];
        return;
    }
    for (MiransasCleanupEntry *e in entries) e.selected = NO;

    NSWindow *parent = self.window;
    if (!parent) return;

    MiransasCleanupSheet *sheet = [[MiransasCleanupSheet alloc]
        initWithTitle:@"Large Files"
             subtitle:@"Select files to move to Trash. Items will be moved to the Trash, not permanently deleted."
              entries:entries
         extraWarning:@"This may include files you still need. Review carefully."];

    __block MiransasCleanupSheet *holder = sheet;
    __unsafe_unretained MiransasStorageTab *weakSelf = self;
    [sheet beginSheetForWindow:parent
                    completion:^(BOOL didTrash, NSUInteger count, uint64_t bytes) {
        if (didTrash) {
            [MiransasCleanup invalidateLargeFilesEntriesCache];
            [weakSelf kickoffLargeFilesScan];
            (void)count; (void)bytes;
        }
        [holder release];
        holder = nil;
    }];
}

#pragma mark - Cleanup: stale project artifacts

- (void)staleArtifactsAction {
    if (_staleArtifactsScanInFlight) return;
    if (_staleArtifactsScanLoaded) {
        [self openStaleArtifactsReview];
    } else {
        [self kickoffStaleArtifactsScan];
    }
}

- (void)kickoffStaleArtifactsScan {
    if (_staleArtifactsScanInFlight) return;
    _staleArtifactsScanInFlight = YES;
    [_staleArtifactsCard setStatsText:@"Scanning ~/ for stale artifacts…"];
    [_staleArtifactsCard setActionEnabled:NO];
    [_staleArtifactsCard setActionHidden:NO];
    [_staleArtifactsCard setScanning:YES];

    __unsafe_unretained MiransasStorageTab *weakSelf = self;
    [MiransasCleanup
        loadStaleArtifactsEntriesWithProgress:^(NSUInteger checked, NSUInteger total) {
            [weakSelf onStaleArtifactsProgress:checked total:total];
        }
        completion:^(NSArray<MiransasCleanupEntry *> *entries) {
            [weakSelf onStaleArtifactsScanLoaded:entries];
        }];
}

- (void)onStaleArtifactsProgress:(NSUInteger)checked total:(NSUInteger)total {
    if (!_staleArtifactsScanInFlight) return;
    if (total == 0) {
        [_staleArtifactsCard setStatsText:@"Scanning ~/ for stale artifacts…"];
    } else {
        [_staleArtifactsCard setStatsText:
            [NSString stringWithFormat:@"Scanning… %lu of %lu projects checked",
                                       (unsigned long)checked,
                                       (unsigned long)total]];
    }
}

- (void)onStaleArtifactsScanLoaded:(NSArray<MiransasCleanupEntry *> *)entries {
    _staleArtifactsScanInFlight = NO;
    _staleArtifactsScanLoaded = YES;
    uint64_t total = 0;
    for (MiransasCleanupEntry *e in entries) total += e.bytes;
    _staleArtifactsTotalBytes = total;
    _staleArtifactsEntryCount = entries.count;
    [_staleArtifactsCard setScanning:NO];
    [self refreshStaleArtifactsStats];
}

- (void)refreshStaleArtifactsStats {
    if (!_staleArtifactsScanLoaded) {
        [_staleArtifactsCard setStatsText:@"Not scanned yet"];
        [_staleArtifactsCard setEmptyStateSymbol:@"folder.badge.questionmark"];
        [_staleArtifactsCard setActionTitle:@"Scan now"];
        [_staleArtifactsCard setActionEnabled:YES];
        [_staleArtifactsCard setActionHidden:NO];
        return;
    }
    [_staleArtifactsCard setActionTitle:@"Review & Clean →"];
    [_staleArtifactsCard setActionPrimary:YES];
    if (_staleArtifactsEntryCount == 0) {
        [_staleArtifactsCard setStatsText:@"No stale artifacts found"];
        [_staleArtifactsCard setEmptyStateSymbol:@"folder.badge.questionmark"];
        [_staleArtifactsCard setActionEnabled:NO];
        [_staleArtifactsCard setActionHidden:YES];
        return;
    }
    [_staleArtifactsCard setStatsText:
        [NSString stringWithFormat:@"%@ across %lu folder%s",
                                   [MiransasCleanup formatBytes:_staleArtifactsTotalBytes],
                                   (unsigned long)_staleArtifactsEntryCount,
                                   _staleArtifactsEntryCount == 1 ? "" : "s"]];
    [_staleArtifactsCard setEmptyStateSymbol:nil];
    [_staleArtifactsCard setActionEnabled:YES];
    [_staleArtifactsCard setActionHidden:NO];
}

- (void)openStaleArtifactsReview {
    NSArray<MiransasCleanupEntry *> *entries = [MiransasCleanup cachedStaleArtifactsEntries];
    if (!entries) {
        [self kickoffStaleArtifactsScan];
        return;
    }
    for (MiransasCleanupEntry *e in entries) e.selected = NO;

    NSWindow *parent = self.window;
    if (!parent) return;

    MiransasCleanupSheet *sheet = [[MiransasCleanupSheet alloc]
        initWithTitle:@"Stale Project Artifacts"
             subtitle:@"Select folders to move to Trash. Items will be moved to the Trash, not permanently deleted."
              entries:entries
         extraWarning:@"These belong to projects you haven't touched in 30+ days. They'll regenerate on next build with npm/cargo/etc."];

    __block MiransasCleanupSheet *holder = sheet;
    __unsafe_unretained MiransasStorageTab *weakSelf = self;
    [sheet beginSheetForWindow:parent
                    completion:^(BOOL didTrash, NSUInteger count, uint64_t bytes) {
        if (didTrash) {
            [MiransasCleanup invalidateStaleArtifactsEntriesCache];
            [weakSelf kickoffStaleArtifactsScan];
            (void)count; (void)bytes;
        }
        [holder release];
        holder = nil;
    }];
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    m_set_layer_bg(self.layer, [NSColor windowBackgroundColor], self);
    [self setNeedsDisplay:YES];
}

@end
