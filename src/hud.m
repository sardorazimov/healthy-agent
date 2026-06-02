#include "agent.h"
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
    [label setTextColor:[[NSColor whiteColor] colorWithAlphaComponent:alpha]];
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

@interface MiransasMenuController : NSObject
@property(nonatomic, strong) NSStatusItem *statusItem;
@end

@implementation MiransasMenuController

- (instancetype)init {
    self = [super init];
    if (!self) {
        return nil;
    }

    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.title = @"Pulse";

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Miransas Pulse"];
    [menu addItemWithTitle:@"Miransas Pulse Running" action:nil keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];
    self.statusItem.menu = menu;
    return self;
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
