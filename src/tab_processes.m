#import "tab_processes.h"
#import "ui_helpers.h"

#pragma mark - Row wrapper

@interface MiransasProcessRow : NSObject
@property(nonatomic, copy)   NSString *name;
@property(nonatomic, assign) int pid;
@property(nonatomic, assign) double cpu;
@property(nonatomic, assign) double ramMB;
@end

@implementation MiransasProcessRow
- (void)dealloc {
    [_name release];
    [super dealloc];
}
@end

#pragma mark - Helpers

static NSTableColumn *make_column(NSString *identifier, NSString *title,
                                  CGFloat width, CGFloat minWidth,
                                  NSTextAlignment alignment, BOOL monospaced,
                                  BOOL defaultAscending,
                                  NSTableColumnResizingOptions resizingMask) {
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:identifier];
    col.title = title;
    col.width = width;
    col.minWidth = minWidth;
    col.resizingMask = resizingMask;

    NSTextFieldCell *cell = [[NSTextFieldCell alloc] initTextCell:@""];
    [cell setAlignment:alignment];
    [cell setLineBreakMode:NSLineBreakByTruncatingTail];
    if (monospaced) {
        [cell setFont:[NSFont monospacedDigitSystemFontOfSize:11.0
                                                       weight:NSFontWeightRegular]];
    } else {
        [cell setFont:[NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular]];
    }
    col.dataCell = cell;
    [cell release];

    [col.headerCell setAlignment:alignment];
    [col.headerCell setFont:[NSFont systemFontOfSize:11.0 weight:NSFontWeightSemibold]];

    NSSortDescriptor *sd = [[NSSortDescriptor alloc]
                            initWithKey:identifier ascending:defaultAscending];
    col.sortDescriptorPrototype = sd;
    [sd release];

    return col;
}

static NSTextField *section_label(NSString *text) {
    NSTextField *f = [[NSTextField alloc] init];
    [f setBezeled:NO];
    [f setDrawsBackground:NO];
    [f setEditable:NO];
    [f setSelectable:NO];
    [f setStringValue:text];
    [f setFont:[NSFont systemFontOfSize:11.0 weight:NSFontWeightSemibold]];
    [f setTextColor:[NSColor systemOrangeColor]];
    return f;
}

#pragma mark - Tab

@interface MiransasProcessesTab () <NSTableViewDataSource, NSTableViewDelegate>
@end

@implementation MiransasProcessesTab {
    NSTextField  *_cpuTitle;
    NSTextField  *_ramTitle;
    NSScrollView *_cpuScroll;
    NSScrollView *_ramScroll;
    NSTableView  *_cpuTable;
    NSTableView  *_ramTable;

    NSMutableArray<MiransasProcessRow *> *_cpuRows;
    NSMutableArray<MiransasProcessRow *> *_ramRows;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (!self) return nil;
    self.wantsLayer = YES;
    self.layer.backgroundColor = [[NSColor windowBackgroundColor] CGColor];

    _cpuRows = [[NSMutableArray alloc] init];
    _ramRows = [[NSMutableArray alloc] init];

    _cpuTitle = section_label(@"TOP BY CPU");
    [self addSubview:_cpuTitle];

    _ramTitle = section_label(@"TOP BY RAM");
    [self addSubview:_ramTitle];

    _cpuTable = [self buildTableWithDefaultSortKey:@"cpu" ascending:NO];
    _ramTable = [self buildTableWithDefaultSortKey:@"ramMB" ascending:NO];

    _cpuScroll = [self wrapTable:_cpuTable];
    _ramScroll = [self wrapTable:_ramTable];

    [self addSubview:_cpuScroll];
    [self addSubview:_ramScroll];

    return self;
}

- (NSTableView *)buildTableWithDefaultSortKey:(NSString *)key ascending:(BOOL)asc {
    NSTableView *tv = [[NSTableView alloc] initWithFrame:NSZeroRect];
    [tv setDataSource:self];
    [tv setDelegate:self];
    [tv setAllowsColumnReordering:NO];
    [tv setAllowsColumnResizing:YES];
    [tv setColumnAutoresizingStyle:NSTableViewSequentialColumnAutoresizingStyle];
    [tv setUsesAlternatingRowBackgroundColors:YES];
    [tv setRowHeight:20.0];
    [tv setIntercellSpacing:NSMakeSize(8.0, 2.0)];
    [tv setAllowsMultipleSelection:NO];
    [tv setAllowsEmptySelection:YES];
    [tv setBackgroundColor:[NSColor clearColor]];
    [tv setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleRegular];

    NSTableColumn *nameCol = make_column(@"name",  @"Process", 220.0, 100.0,
                                         NSTextAlignmentLeft,  NO,  YES,
                                         NSTableColumnAutoresizingMask
                                         | NSTableColumnUserResizingMask);
    NSTableColumn *pidCol  = make_column(@"pid",   @"PID",      60.0,  40.0,
                                         NSTextAlignmentRight, YES, YES,
                                         NSTableColumnUserResizingMask);
    NSTableColumn *cpuCol  = make_column(@"cpu",   @"CPU %",    70.0,  50.0,
                                         NSTextAlignmentRight, YES, NO,
                                         NSTableColumnUserResizingMask);
    NSTableColumn *ramCol  = make_column(@"ramMB", @"RAM MB",   80.0,  60.0,
                                         NSTextAlignmentRight, YES, NO,
                                         NSTableColumnUserResizingMask);

    [tv addTableColumn:nameCol];
    [tv addTableColumn:pidCol];
    [tv addTableColumn:cpuCol];
    [tv addTableColumn:ramCol];

    [nameCol release];
    [pidCol  release];
    [cpuCol  release];
    [ramCol  release];

    NSSortDescriptor *initial = [[NSSortDescriptor alloc] initWithKey:key
                                                            ascending:asc];
    [tv setSortDescriptors:@[initial]];
    [initial release];

    return tv;
}

- (NSScrollView *)wrapTable:(NSTableView *)tv {
    NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    [sv setHasVerticalScroller:YES];
    [sv setHasHorizontalScroller:NO];
    [sv setBorderType:NSNoBorder];
    [sv setAutohidesScrollers:YES];
    [sv setDrawsBackground:NO];
    [sv setDocumentView:tv];
    return sv;
}

- (void)layout {
    [super layout];
    NSRect b = self.bounds;
    CGFloat pad = 24.0;
    CGFloat titleH = 16.0;
    CGFloat titleGap = 6.0;
    CGFloat sectionGap = 16.0;

    CGFloat available = b.size.height - 2.0 * pad
                      - 2.0 * (titleH + titleGap)
                      - sectionGap;
    CGFloat tableH = floor(available / 2.0);
    if (tableH < 80.0) tableH = 80.0;

    CGFloat innerW = b.size.width - 2.0 * pad;

    CGFloat cpuTitleY = b.size.height - pad - titleH;
    _cpuTitle.frame  = NSMakeRect(pad, cpuTitleY, innerW, titleH);

    CGFloat cpuScrollY = cpuTitleY - titleGap - tableH;
    _cpuScroll.frame = NSMakeRect(pad, cpuScrollY, innerW, tableH);

    CGFloat ramTitleY = cpuScrollY - sectionGap - titleH;
    _ramTitle.frame  = NSMakeRect(pad, ramTitleY, innerW, titleH);

    CGFloat ramScrollY = ramTitleY - titleGap - tableH;
    _ramScroll.frame = NSMakeRect(pad, ramScrollY, innerW, tableH);
}

#pragma mark - Data

- (void)updateWithSnapshot:(const agent_snapshot_t *)snapshot {
    if (!snapshot) return;
    const process_snapshot_t *ps = &snapshot->processes;

    NSMutableArray *all = [NSMutableArray arrayWithCapacity:ps->count];
    for (size_t i = 0; i < ps->count; i++) {
        const process_metrics_t *p = &ps->processes[i];
        MiransasProcessRow *row = [[MiransasProcessRow alloc] init];
        row.name = [NSString stringWithUTF8String:p->name];
        row.pid = p->pid;
        row.cpu = p->cpu_percent;
        row.ramMB = (double)p->resident_bytes / (1024.0 * 1024.0);
        [all addObject:row];
        [row release];
    }

    NSSortDescriptor *byCpu = [[NSSortDescriptor alloc] initWithKey:@"cpu" ascending:NO];
    NSSortDescriptor *byRam = [[NSSortDescriptor alloc] initWithKey:@"ramMB" ascending:NO];
    NSArray *cpuSorted = [all sortedArrayUsingDescriptors:@[byCpu]];
    NSArray *ramSorted = [all sortedArrayUsingDescriptors:@[byRam]];
    [byCpu release];
    [byRam release];

    NSUInteger n = MIN((NSUInteger)10, all.count);
    NSArray *top10Cpu = (n > 0) ? [cpuSorted subarrayWithRange:NSMakeRange(0, n)] : @[];
    NSArray *top10Ram = (n > 0) ? [ramSorted subarrayWithRange:NSMakeRange(0, n)] : @[];

    [_cpuRows removeAllObjects];
    [_cpuRows addObjectsFromArray:
        [top10Cpu sortedArrayUsingDescriptors:_cpuTable.sortDescriptors]];

    [_ramRows removeAllObjects];
    [_ramRows addObjectsFromArray:
        [top10Ram sortedArrayUsingDescriptors:_ramTable.sortDescriptors]];

    [_cpuTable reloadData];
    [_ramTable reloadData];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (tableView == _cpuTable) ? (NSInteger)_cpuRows.count
                                    : (NSInteger)_ramRows.count;
}

- (id)tableView:(NSTableView *)tableView
    objectValueForTableColumn:(NSTableColumn *)column
    row:(NSInteger)rowIndex {
    NSMutableArray<MiransasProcessRow *> *src =
        (tableView == _cpuTable) ? _cpuRows : _ramRows;
    if (rowIndex < 0 || (NSUInteger)rowIndex >= src.count) return @"";
    MiransasProcessRow *r = src[(NSUInteger)rowIndex];

    NSString *ident = column.identifier;
    if ([ident isEqualToString:@"name"])  return r.name ?: @"";
    if ([ident isEqualToString:@"pid"])   return [NSString stringWithFormat:@"%d", r.pid];
    if ([ident isEqualToString:@"cpu"])   return [NSString stringWithFormat:@"%.1f", r.cpu];
    if ([ident isEqualToString:@"ramMB"]) return [NSString stringWithFormat:@"%.0f", r.ramMB];
    return @"";
}

- (void)tableView:(NSTableView *)tableView
    sortDescriptorsDidChange:(NSArray<NSSortDescriptor *> *)oldDescriptors {
    (void)oldDescriptors;
    NSMutableArray<MiransasProcessRow *> *src =
        (tableView == _cpuTable) ? _cpuRows : _ramRows;
    NSArray *sorted = [src sortedArrayUsingDescriptors:tableView.sortDescriptors];
    [src removeAllObjects];
    [src addObjectsFromArray:sorted];
    [tableView reloadData];
}

#pragma mark - NSTableViewDelegate

- (void)tableView:(NSTableView *)tableView
    willDisplayCell:(id)cell
    forTableColumn:(NSTableColumn *)column
    row:(NSInteger)rowIndex {
    if (![cell isKindOfClass:[NSTextFieldCell class]]) return;
    NSTextFieldCell *tc = (NSTextFieldCell *)cell;

    NSMutableArray<MiransasProcessRow *> *src =
        (tableView == _cpuTable) ? _cpuRows : _ramRows;
    if (rowIndex < 0 || (NSUInteger)rowIndex >= src.count) {
        [tc setTextColor:[NSColor labelColor]];
        return;
    }
    MiransasProcessRow *r = src[(NSUInteger)rowIndex];

    if ([column.identifier isEqualToString:@"cpu"] && r.cpu >= 50.0) {
        [tc setTextColor:[NSColor systemOrangeColor]];
    } else {
        [tc setTextColor:[NSColor labelColor]];
    }
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    m_set_layer_bg(self.layer, [NSColor windowBackgroundColor], self);
    [self setNeedsDisplay:YES];
}

@end
