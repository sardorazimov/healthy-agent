#include "agent.h"

#include <errno.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>

#import <Cocoa/Cocoa.h>

static int compare_by_resident_desc(const void *a, const void *b) {
    const process_metrics_t *pa = (const process_metrics_t *)a;
    const process_metrics_t *pb = (const process_metrics_t *)b;
    if (pb->resident_bytes > pa->resident_bytes) return 1;
    if (pb->resident_bytes < pa->resident_bytes) return -1;
    return 0;
}

@interface MiransasHudController : NSObject
@property(nonatomic, strong) NSPanel *panel;
@end

@implementation MiransasHudController

- (instancetype)initWithSnapshot:(const agent_snapshot_t *)snapshot {
    self = [super init];
    if (!self) {
        return nil;
    }

    NSScreen *screen = [NSScreen mainScreen];
    NSRect screenFrame = [screen visibleFrame];
    CGFloat width = 360.0;
    CGFloat height = 184.0;
    NSRect frame = NSMakeRect(NSMaxX(screenFrame) - width - 24.0,
                              NSMaxY(screenFrame) - height - 24.0,
                              width,
                              height);

    self.panel = [[NSPanel alloc] initWithContentRect:frame
                                            styleMask:NSWindowStyleMaskBorderless
                                              backing:NSBackingStoreBuffered
                                                defer:NO];
    [self.panel setOpaque:NO];
    [self.panel setAlphaValue:0.94];
    [self.panel setLevel:NSFloatingWindowLevel];
    [self.panel setHidesOnDeactivate:NO];
    [self.panel setReleasedWhenClosed:NO];
    [self.panel setIgnoresMouseEvents:NO];
    [self.panel setBackgroundColor:[NSColor clearColor]];

    NSVisualEffectView *blurView = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
    [blurView setMaterial:NSVisualEffectMaterialHUDWindow];
    [blurView setBlendingMode:NSVisualEffectBlendingModeBehindWindow];
    [blurView setState:NSVisualEffectStateActive];
    [blurView setWantsLayer:YES];
    [blurView.layer setCornerRadius:18.0];
    [blurView.layer setMasksToBounds:YES];

    NSTextField *title = [self labelWithFrame:NSMakeRect(22, 140, 316, 24)
                                         text:@"Miransas Pulse"
                                     fontSize:18.0
                                       weight:NSFontWeightSemibold
                                        alpha:1.0];

    NSString *bodyText = [NSString stringWithFormat:@"Score %d  |  CPU %.1f%%  |  RAM %@/%@ MB",
                          snapshot->health_score,
                          snapshot->system.cpu_usage,
                          @(snapshot->system.free_ram),
                          @(snapshot->system.total_ram)];
    NSTextField *body = [self labelWithFrame:NSMakeRect(22, 110, 316, 22)
                                        text:bodyText
                                    fontSize:14.0
                                      weight:NSFontWeightRegular
                                       alpha:0.88];

    NSString *topText = @"No process data yet";
    if (snapshot->processes.count > 0) {
        const process_metrics_t *top = &snapshot->processes.processes[0];
        topText = [NSString stringWithFormat:@"Top: %s  CPU %.1f%%  RAM %.1f MB",
                   top->name,
                   top->cpu_percent,
                   (double)top->resident_bytes / 1024.0 / 1024.0];
    }
    NSTextField *top = [self labelWithFrame:NSMakeRect(22, 80, 316, 20)
                                       text:topText
                                   fontSize:13.0
                                     weight:NSFontWeightRegular
                                      alpha:0.82];

    NSTextField *foot = [self labelWithFrame:NSMakeRect(22, 36, 316, 18)
                                        text:@"Local API: http://127.0.0.1:9876/metrics"
                                    fontSize:12.0
                                      weight:NSFontWeightRegular
                                       alpha:0.62];

    [blurView addSubview:title];
    [blurView addSubview:body];
    [blurView addSubview:top];
    [blurView addSubview:foot];
    [self.panel setContentView:blurView];

    return self;
}

- (NSTextField *)labelWithFrame:(NSRect)frame
                           text:(NSString *)text
                       fontSize:(CGFloat)fontSize
                         weight:(NSFontWeight)weight
                          alpha:(CGFloat)alpha {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    [label setStringValue:text];
    [label setBezeled:NO];
    [label setDrawsBackground:NO];
    [label setEditable:NO];
    [label setSelectable:NO];
    [label setTextColor:[[NSColor labelColor] colorWithAlphaComponent:alpha]];
    [label setFont:[NSFont systemFontOfSize:fontSize weight:weight]];
    return label;
}

- (void)show {
    [self.panel makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)close {
    [self.panel close];
}

@end

void show_health_hud(const agent_snapshot_t *snapshot) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

        MiransasHudController *controller = [[MiransasHudController alloc] initWithSnapshot:snapshot];
        [controller show];

        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:4.0];
        while ([deadline timeIntervalSinceNow] > 0.0) {
            @autoreleasepool {
                NSEvent *event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                                    untilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]
                                                       inMode:NSDefaultRunLoopMode
                                                      dequeue:YES];
                if (event) {
                    [NSApp sendEvent:event];
                }
                [NSApp updateWindows];
            }
        }

        [controller close];
    }
}

@interface MiransasMenuController : NSObject {
    agent_snapshot_t _snapshot;
}
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) NSTimer *timer;
- (void)tick:(NSTimer *)timer;
- (void)killProcess:(NSMenuItem *)sender;
@end

@implementation MiransasMenuController

- (instancetype)init {
    self = [super init];
    if (!self) {
        return nil;
    }

    memset(&_snapshot, 0, sizeof(_snapshot));

    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.title = @"♥ --";
    self.statusItem.menu = [[NSMenu alloc] initWithTitle:@"Miransas Pulse"];
    [self.statusItem.menu setAutoenablesItems:NO];

    // Warm-up: process.c per-pid CPU cache'ini doldur. İlk gerçek tick
    // INTERVAL_SEC sonra ateş edince delta hesaplanabilir.
    process_snapshot_t warmup;
    collect_process_snapshot(&warmup);

    self.timer = [NSTimer scheduledTimerWithTimeInterval:(NSTimeInterval)INTERVAL_SEC
                                                  target:self
                                                selector:@selector(tick:)
                                                userInfo:nil
                                                 repeats:YES];
    return self;
}

- (void)tick:(NSTimer *)timer {
    (void)timer;

    collect_metrics(&_snapshot.system);
    collect_process_snapshot(&_snapshot.processes);
    _snapshot.health_score = calculate_system_health_score(&_snapshot.system, &_snapshot.processes);
    api_server_publish(&_snapshot);

    self.statusItem.button.title = [NSString stringWithFormat:@"♥ %d", _snapshot.health_score];

    NSMenu *menu = self.statusItem.menu;
    [menu removeAllItems];

    NSColor *scoreColor;
    if (_snapshot.health_score > 70) {
        scoreColor = [NSColor systemGreenColor];
    } else if (_snapshot.health_score >= 40) {
        scoreColor = [NSColor systemOrangeColor];
    } else {
        scoreColor = [NSColor systemRedColor];
    }

    NSFont *menuFont = [NSFont menuBarFontOfSize:0];
    NSString *scorePrefix = @"Score ";
    NSString *scoreValue = [NSString stringWithFormat:@"%d", _snapshot.health_score];
    NSString *sysSuffix = [NSString stringWithFormat:@"   CPU %.1f%%   RAM %llu/%llu MB",
                           _snapshot.system.cpu_usage,
                           (unsigned long long)_snapshot.system.free_ram,
                           (unsigned long long)_snapshot.system.total_ram];

    NSMutableAttributedString *sysAttr = [[NSMutableAttributedString alloc] init];
    [sysAttr appendAttributedString:[[NSAttributedString alloc] initWithString:scorePrefix attributes:@{
        NSForegroundColorAttributeName: [NSColor labelColor],
        NSFontAttributeName: menuFont
    }]];
    [sysAttr appendAttributedString:[[NSAttributedString alloc] initWithString:scoreValue attributes:@{
        NSForegroundColorAttributeName: scoreColor,
        NSFontAttributeName: [NSFont systemFontOfSize:menuFont.pointSize weight:NSFontWeightSemibold]
    }]];
    [sysAttr appendAttributedString:[[NSAttributedString alloc] initWithString:sysSuffix attributes:@{
        NSForegroundColorAttributeName: [NSColor labelColor],
        NSFontAttributeName: menuFont
    }]];

    NSMenuItem *sysItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    [sysItem setAttributedTitle:sysAttr];
    [sysItem setEnabled:YES];
    [menu addItem:sysItem];

    [menu addItem:[NSMenuItem separatorItem]];

    NSDictionary *headerAttrs = @{
        NSForegroundColorAttributeName: [NSColor systemOrangeColor],
        NSFontAttributeName: [NSFont systemFontOfSize:[NSFont smallSystemFontSize] weight:NSFontWeightSemibold]
    };
    NSMenuItem *cpuHeader = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    [cpuHeader setAttributedTitle:[[NSAttributedString alloc] initWithString:@"— En cok CPU —"
                                                                  attributes:headerAttrs]];
    [cpuHeader setEnabled:NO];
    [menu addItem:cpuHeader];

    size_t topCount = _snapshot.processes.count < 5 ? _snapshot.processes.count : 5;
    if (topCount == 0) {
        NSMenuItem *empty = [[NSMenuItem alloc] initWithTitle:@"No process data yet" action:nil keyEquivalent:@""];
        [empty setEnabled:NO];
        [menu addItem:empty];
    } else {
        for (size_t i = 0; i < topCount; i++) {
            const process_metrics_t *p = &_snapshot.processes.processes[i];
            NSString *line = [NSString stringWithFormat:@"%s   CPU %.1f%%   RAM %.0f MB",
                              p->name,
                              p->cpu_percent,
                              (double)p->resident_bytes / 1048576.0];
            NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:line
                                                          action:@selector(killProcess:)
                                                   keyEquivalent:@""];
            [item setTarget:self];
            [item setTag:p->pid];
            [item setRepresentedObject:[NSString stringWithUTF8String:p->name]];
            [menu addItem:item];
        }
    }

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *ramHeader = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    [ramHeader setAttributedTitle:[[NSAttributedString alloc] initWithString:@"— En cok RAM —"
                                                                  attributes:headerAttrs]];
    [ramHeader setEnabled:NO];
    [menu addItem:ramHeader];

    if (_snapshot.processes.count == 0) {
        NSMenuItem *empty = [[NSMenuItem alloc] initWithTitle:@"No process data yet" action:nil keyEquivalent:@""];
        [empty setEnabled:NO];
        [menu addItem:empty];
    } else {
        process_metrics_t ramSorted[MAX_TRACKED_PROCESSES];
        size_t ramCount = _snapshot.processes.count;
        memcpy(ramSorted, _snapshot.processes.processes, ramCount * sizeof(process_metrics_t));
        qsort(ramSorted, ramCount, sizeof(process_metrics_t), compare_by_resident_desc);

        size_t ramTop = ramCount < 5 ? ramCount : 5;
        for (size_t i = 0; i < ramTop; i++) {
            const process_metrics_t *p = &ramSorted[i];
            NSString *line = [NSString stringWithFormat:@"%s   RAM %.0f MB",
                              p->name,
                              (double)p->resident_bytes / 1048576.0];
            NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:line
                                                          action:@selector(killProcess:)
                                                   keyEquivalent:@""];
            [item setTarget:self];
            [item setTag:p->pid];
            [item setRepresentedObject:[NSString stringWithUTF8String:p->name]];
            [menu addItem:item];
        }
    }

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Quit Miransas Pulse"
                                                  action:@selector(terminate:)
                                           keyEquivalent:@"q"];
    [quit setTarget:NSApp];
    [menu addItem:quit];
}

- (void)killProcess:(NSMenuItem *)sender {
    pid_t pid = (pid_t)[sender tag];
    NSString *name = [sender representedObject];
    if (pid <= 0) {
        return;
    }

    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:[NSString stringWithFormat:@"%@ (pid %d) sonlandirilsin mi?",
                                                     name ?: @"Process", pid]];
    [alert setInformativeText:@"SIGTERM gonderilecek."];
    [alert addButtonWithTitle:@"Sonlandir"];
    [alert addButtonWithTitle:@"Iptal"];
    [alert setAlertStyle:NSAlertStyleWarning];

    [NSApp activateIgnoringOtherApps:YES];
    NSModalResponse response = [alert runModal];
    if (response == NSAlertFirstButtonReturn) {
        if (kill(pid, SIGTERM) != 0) {
            fprintf(stderr, "[Miransas-Pulse] kill(%d, SIGTERM) basarisiz: %s\n",
                    pid, strerror(errno));
        }
    }
}

- (void)dealloc {
    [self.timer invalidate];
    [super dealloc];
}

@end

void show_menubar_app(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        __unused MiransasMenuController *controller = [[MiransasMenuController alloc] init];
        [NSApp run];
    }
}
