#import "detail_window.h"
#import "tab_overview.h"
#import "tab_processes.h"
#import "tab_history.h"
#import "tab_storage.h"
#import "tab_network.h"

#pragma mark - Sidebar row

@interface MiransasSidebarRow : NSView
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *symbolName;
@property(nonatomic, assign, getter=isSelected) BOOL selected;
@property(nonatomic, copy) void (^onClick)(void);
@end

@implementation MiransasSidebarRow {
    NSTextField *_label;
    NSImageView *_iconView;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (!self) return nil;

    self.wantsLayer = YES;
    self.layer.cornerRadius = 6.0;

    CGFloat iconSize = 18.0;
    _iconView = [[NSImageView alloc] initWithFrame:NSMakeRect(12.0,
                                                              (frameRect.size.height - iconSize) / 2.0,
                                                              iconSize, iconSize)];
    [_iconView setImageScaling:NSImageScaleProportionallyUpOrDown];
    [_iconView setAutoresizingMask:NSViewMaxXMargin];
    [self addSubview:_iconView];

    CGFloat labelHeight = 17.0;
    _label = [[NSTextField alloc] initWithFrame:NSMakeRect(40.0,
                                                           (frameRect.size.height - labelHeight) / 2.0,
                                                           frameRect.size.width - 48.0,
                                                           labelHeight)];
    [_label setBezeled:NO];
    [_label setDrawsBackground:NO];
    [_label setEditable:NO];
    [_label setSelectable:NO];
    [_label setFont:[NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium]];
    [_label setTextColor:[NSColor labelColor]];
    [_label setAutoresizingMask:NSViewWidthSizable];
    [self addSubview:_label];

    return self;
}

- (void)setTitle:(NSString *)title {
    _title = [title copy];
    _label.stringValue = title ?: @"";
}

- (void)setSymbolName:(NSString *)symbolName {
    _symbolName = [symbolName copy];
    if (@available(macOS 11.0, *)) {
        NSImage *image = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:nil];
        _iconView.image = image;
        _iconView.contentTintColor = [NSColor labelColor];
    }
}

- (void)setSelected:(BOOL)selected {
    _selected = selected;
    if (selected) {
        self.layer.backgroundColor = [[NSColor selectedContentBackgroundColor] CGColor];
        _label.textColor = [NSColor whiteColor];
        if (@available(macOS 11.0, *)) {
            _iconView.contentTintColor = [NSColor whiteColor];
        }
    } else {
        self.layer.backgroundColor = [[NSColor clearColor] CGColor];
        _label.textColor = [NSColor labelColor];
        if (@available(macOS 11.0, *)) {
            _iconView.contentTintColor = [NSColor labelColor];
        }
    }
}

- (void)mouseDown:(NSEvent *)event {
    (void)event;
    if (self.onClick) {
        self.onClick();
    }
}

- (void)resetCursorRects {
    [self addCursorRect:self.bounds cursor:[NSCursor pointingHandCursor]];
}

@end

#pragma mark - Detail window

@interface MiransasDetailWindow () <NSWindowDelegate> {
    agent_snapshot_t _lastSnapshot;
    BOOL _hasSnapshot;
    BOOL _firstShow;
}
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) NSView *contentArea;
@property(nonatomic, strong) NSView *currentTabView;
@property(nonatomic, strong) NSTextField *headerTitle;
@property(nonatomic, strong) NSMutableArray<MiransasSidebarRow *> *sidebarRows;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSView *> *tabViews;
@property(nonatomic, assign) NSUInteger selectedIndex;
@end

@implementation MiransasDetailWindow

+ (instancetype)shared {
    static MiransasDetailWindow *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[MiransasDetailWindow alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _sidebarRows = [[NSMutableArray alloc] init];
    _tabViews = [[NSMutableDictionary alloc] init];
    _selectedIndex = 0;
    _firstShow = YES;
    return self;
}

- (NSView *)tabViewForIndex:(NSUInteger)index {
    NSNumber *key = @(index);
    NSView *view = self.tabViews[key];
    if (view) return view;

    NSRect bounds = self.contentArea.bounds;
    if (index == 0) {
        view = [[MiransasOverviewTab alloc] initWithFrame:bounds];
    } else if (index == 1) {
        view = [[MiransasProcessesTab alloc] initWithFrame:bounds];
    } else if (index == 2) {
        view = [[MiransasHistoryTab alloc] initWithFrame:bounds];
    } else if (index == 3) {
        view = [[MiransasStorageTab alloc] initWithFrame:bounds];
    } else if (index == 4) {
        view = [[MiransasNetworkTab alloc] initWithFrame:bounds];
    } else {
        view = [[NSView alloc] initWithFrame:bounds];
        NSTextField *label = [[NSTextField alloc] init];
        [label setBezeled:NO];
        [label setDrawsBackground:NO];
        [label setEditable:NO];
        [label setSelectable:NO];
        [label setStringValue:[NSString stringWithFormat:@"%@ — coming soon",
                               self.sidebarRows[index].title]];
        [label setTextColor:[NSColor secondaryLabelColor]];
        [label setFont:[NSFont systemFontOfSize:16.0 weight:NSFontWeightRegular]];
        [label sizeToFit];
        NSRect lf = label.frame;
        lf.origin.x = (bounds.size.width - lf.size.width) / 2.0;
        lf.origin.y = (bounds.size.height - lf.size.height) / 2.0;
        label.frame = lf;
        [label setAutoresizingMask:NSViewMinXMargin | NSViewMaxXMargin
                                  | NSViewMinYMargin | NSViewMaxYMargin];
        [view addSubview:label];
    }
    [view setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    self.tabViews[key] = view;
    return view;
}

- (void)buildWindowIfNeeded {
    if (self.window) return;

    NSRect frame = NSMakeRect(0.0, 0.0, 720.0, 520.0);
    NSUInteger style = NSWindowStyleMaskTitled
                     | NSWindowStyleMaskClosable
                     | NSWindowStyleMaskMiniaturizable
                     | NSWindowStyleMaskResizable
                     | NSWindowStyleMaskFullSizeContentView;

    self.window = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:style
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    [self.window setTitle:@"Miransas Pulse"];
    [self.window setTitlebarAppearsTransparent:YES];
    [self.window setTitleVisibility:NSWindowTitleHidden];
    [self.window setMovableByWindowBackground:YES];
    [self.window setMinSize:NSMakeSize(600.0, 400.0)];
    [self.window setDelegate:self];
    [self.window setReleasedWhenClosed:NO];

    NSView *root = self.window.contentView;
    root.wantsLayer = YES;

    CGFloat sidebarWidth = 180.0;
    CGFloat headerHeight = 44.0;
    NSRect bounds = root.bounds;

    NSVisualEffectView *sidebarBg = [[NSVisualEffectView alloc]
        initWithFrame:NSMakeRect(0.0, 0.0, sidebarWidth, bounds.size.height)];
    [sidebarBg setMaterial:NSVisualEffectMaterialSidebar];
    [sidebarBg setBlendingMode:NSVisualEffectBlendingModeBehindWindow];
    [sidebarBg setState:NSVisualEffectStateFollowsWindowActiveState];
    [sidebarBg setAutoresizingMask:NSViewHeightSizable];
    [root addSubview:sidebarBg];

    NSArray<NSDictionary *> *tabs = @[
        @{@"title": @"Overview",  @"symbol": @"gauge"},
        @{@"title": @"Processes", @"symbol": @"list.bullet"},
        @{@"title": @"History",   @"symbol": @"chart.line.uptrend.xyaxis"},
        @{@"title": @"Storage",   @"symbol": @"externaldrive"},
        @{@"title": @"Network",   @"symbol": @"network"},
    ];

    CGFloat rowHeight = 34.0;
    CGFloat rowGap = 2.0;
    CGFloat rowsTop = bounds.size.height - headerHeight - 8.0;

    for (NSUInteger i = 0; i < tabs.count; i++) {
        NSDictionary *t = tabs[i];
        NSRect rowFrame = NSMakeRect(8.0,
                                     rowsTop - (CGFloat)(i + 1) * (rowHeight + rowGap),
                                     sidebarWidth - 16.0,
                                     rowHeight);
        MiransasSidebarRow *row = [[MiransasSidebarRow alloc] initWithFrame:rowFrame];
        [row setAutoresizingMask:NSViewMinYMargin];
        row.title = t[@"title"];
        row.symbolName = t[@"symbol"];
        NSUInteger captured = i;
        __unsafe_unretained typeof(self) weakSelf = self;
        row.onClick = ^{ [weakSelf selectTab:captured]; };
        [sidebarBg addSubview:row];
        [self.sidebarRows addObject:row];
    }

    self.contentArea = [[NSView alloc]
        initWithFrame:NSMakeRect(sidebarWidth, 0.0,
                                 bounds.size.width - sidebarWidth,
                                 bounds.size.height - headerHeight)];
    [self.contentArea setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    self.contentArea.wantsLayer = YES;
    self.contentArea.layer.backgroundColor = [[NSColor windowBackgroundColor] CGColor];
    [root addSubview:self.contentArea];

    NSView *header = [[NSView alloc]
        initWithFrame:NSMakeRect(sidebarWidth,
                                 bounds.size.height - headerHeight,
                                 bounds.size.width - sidebarWidth,
                                 headerHeight)];
    [header setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    header.wantsLayer = YES;
    header.layer.backgroundColor = [[NSColor windowBackgroundColor] CGColor];

    self.headerTitle = [[NSTextField alloc]
        initWithFrame:NSMakeRect(16.0, (headerHeight - 18.0) / 2.0,
                                 header.frame.size.width - 100.0, 18.0)];
    [self.headerTitle setBezeled:NO];
    [self.headerTitle setDrawsBackground:NO];
    [self.headerTitle setEditable:NO];
    [self.headerTitle setSelectable:NO];
    [self.headerTitle setStringValue:@"Miransas Pulse"];
    [self.headerTitle setTextColor:[NSColor labelColor]];
    [self.headerTitle setFont:[NSFont systemFontOfSize:14.0 weight:NSFontWeightSemibold]];
    [self.headerTitle setAutoresizingMask:NSViewWidthSizable];
    [header addSubview:self.headerTitle];

    NSButton *quit = [NSButton buttonWithTitle:@"Quit"
                                        target:NSApp
                                        action:@selector(terminate:)];
    [quit setButtonType:NSButtonTypeMomentaryPushIn];
    [quit setBezelStyle:NSBezelStyleRounded];
    [quit setControlSize:NSControlSizeRegular];
    [quit setFont:[NSFont systemFontOfSize:13.0 weight:NSFontWeightRegular]];
    CGFloat quitW = 68.0;
    CGFloat quitH = 24.0;
    NSRect quitFrame = NSMakeRect(header.frame.size.width - quitW - 12.0,
                                  (headerHeight - quitH) / 2.0,
                                  quitW, quitH);
    [quit setFrame:quitFrame];
    [quit setAutoresizingMask:NSViewMinXMargin];
    [header addSubview:quit];

    [root addSubview:header];

    [self selectTab:0];
}

- (void)selectTab:(NSUInteger)index {
    if (index >= self.sidebarRows.count) return;

    self.selectedIndex = index;
    for (NSUInteger i = 0; i < self.sidebarRows.count; i++) {
        self.sidebarRows[i].selected = (i == index);
    }

    [self.currentTabView removeFromSuperview];

    NSView *tab = [self tabViewForIndex:index];
    tab.frame = self.contentArea.bounds;
    self.currentTabView = tab;
    [self.contentArea addSubview:tab];

    if (_hasSnapshot && [tab respondsToSelector:@selector(updateWithSnapshot:)]) {
        [(MiransasOverviewTab *)tab updateWithSnapshot:&_lastSnapshot];
    }
}

- (void)show {
    [self buildWindowIfNeeded];
    if (_firstShow) {
        [self.window center];
        _firstShow = NO;
    }
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)updateWithSnapshot:(const agent_snapshot_t *)snapshot {
    if (!snapshot) return;
    _lastSnapshot = *snapshot;
    _hasSnapshot = YES;

    if (self.headerTitle) {
        NSString *headerText = [NSString stringWithFormat:@"Miransas Pulse   ♥ %d",
                                snapshot->health_score];
        [self.headerTitle setStringValue:headerText];
    }

    if (self.currentTabView &&
        [self.currentTabView respondsToSelector:@selector(updateWithSnapshot:)]) {
        [(MiransasOverviewTab *)self.currentTabView updateWithSnapshot:&_lastSnapshot];
    }
}

- (BOOL)windowShouldClose:(NSWindow *)sender {
    (void)sender;
    [self.window orderOut:nil];
    return NO;
}

@end
