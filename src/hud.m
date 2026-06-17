#include "agent.h"
#import "detail_window.h"
#import "history_ring.h"

#include <errno.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/param.h>

#import <Cocoa/Cocoa.h>

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
- (void)statusBarClicked:(id)sender;
- (void)openDetailWindow:(id)sender;
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
    self.statusItem.button.target = self;
    self.statusItem.button.action = @selector(statusBarClicked:);
    [self.statusItem.button sendActionOn:(NSEventMaskLeftMouseUp | NSEventMaskRightMouseUp)];

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

- (void)statusBarClicked:(id)sender {
    (void)sender;
    NSEvent *event = [NSApp currentEvent];
    BOOL isRightClick = event && (event.type == NSEventTypeRightMouseUp ||
                                  (event.type == NSEventTypeLeftMouseUp &&
                                   (event.modifierFlags & NSEventModifierFlagControl) != 0));

    if (isRightClick) {
        NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Miransas Pulse"];
        [menu setAutoenablesItems:NO];

        NSMenuItem *open = [[NSMenuItem alloc] initWithTitle:@"Open Pulse"
                                                       action:@selector(openDetailWindow:)
                                                keyEquivalent:@""];
        [open setTarget:self];
        [open setEnabled:YES];
        [menu addItem:open];

        [menu addItem:[NSMenuItem separatorItem]];

        NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Quit Miransas Pulse"
                                                       action:@selector(terminate:)
                                                keyEquivalent:@"q"];
        [quit setTarget:NSApp];
        [quit setEnabled:YES];
        [menu addItem:quit];

        [NSMenu popUpContextMenu:menu withEvent:event forView:self.statusItem.button];
    } else {
        [self openDetailWindow:nil];
    }
}

- (void)openDetailWindow:(id)sender {
    (void)sender;
    [[MiransasDetailWindow shared] show];
    if (_snapshot.system.total_ram != 0 || _snapshot.health_score != 0) {
        [[MiransasDetailWindow shared] updateWithSnapshot:&_snapshot];
    }
}

- (void)tick:(NSTimer *)timer {
    (void)timer;

    collect_metrics(&_snapshot.system);
    collect_process_snapshot(&_snapshot.processes);
    _snapshot.health_score = calculate_system_health_score(&_snapshot.system, &_snapshot.processes);
    api_server_publish(&_snapshot);

    self.statusItem.button.title = [NSString stringWithFormat:@"♥ %d", _snapshot.health_score];

    double cpu = _snapshot.system.cpu_usage;
    if (cpu < 0.0) cpu = 0.0;
    uint64_t total = _snapshot.system.total_ram;
    uint64_t freev = _snapshot.system.free_ram;
    double ramFrac = (total > 0) ? ((double)(total - freev) / (double)total) : 0.0;

    double diskFrac = 0.0;
    struct statfs s;
    if (statfs("/", &s) == 0) {
        uint64_t bsize = (uint64_t)s.f_bsize;
        uint64_t totalBytes = (uint64_t)s.f_blocks * bsize;
        uint64_t freeBytes  = (uint64_t)s.f_bavail * bsize;
        if (totalBytes > 0) {
            diskFrac = (double)(totalBytes - freeBytes) / (double)totalBytes;
        }
    }

    [[MiransasHistoryRing shared] appendCPU:cpu
                                ramFraction:ramFrac
                               diskFraction:diskFrac];

    [[MiransasDetailWindow shared] updateWithSnapshot:&_snapshot];
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
