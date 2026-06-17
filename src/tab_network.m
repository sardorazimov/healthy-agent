#import "tab_network.h"

#include <sys/socket.h>
#include <sys/sysctl.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <net/route.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <string.h>

#import <CoreWLAN/CoreWLAN.h>
#import <SystemConfiguration/SystemConfiguration.h>

#pragma mark - Helpers

typedef struct {
    uint64_t rx_bytes;
    uint64_t tx_bytes;
} net_counters_t;

static net_counters_t read_counters(void) {
    net_counters_t out = {0, 0};
    int mib[] = { CTL_NET, PF_ROUTE, 0, AF_LINK, NET_RT_IFLIST2, 0 };
    size_t needed = 0;
    if (sysctl(mib, 6, NULL, &needed, NULL, 0) < 0 || needed == 0) {
        return out;
    }
    char *buf = malloc(needed);
    if (!buf) return out;
    if (sysctl(mib, 6, buf, &needed, NULL, 0) < 0) {
        free(buf);
        return out;
    }
    for (char *p = buf; p < buf + needed; ) {
        struct if_msghdr *ifm = (struct if_msghdr *)p;
        if (ifm->ifm_msglen == 0) break;
        if (ifm->ifm_type == RTM_IFINFO2) {
            struct if_msghdr2 *ifm2 = (struct if_msghdr2 *)ifm;
            struct sockaddr_dl *sdl = (struct sockaddr_dl *)(ifm2 + 1);
            char name[IFNAMSIZ + 1];
            size_t n = sdl->sdl_nlen < IFNAMSIZ ? sdl->sdl_nlen : IFNAMSIZ;
            memcpy(name, sdl->sdl_data, n);
            name[n] = 0;
            if (strncmp(name, "lo", 2) != 0) {
                out.rx_bytes += ifm2->ifm_data.ifi_ibytes;
                out.tx_bytes += ifm2->ifm_data.ifi_obytes;
            }
        }
        p += ifm->ifm_msglen;
    }
    free(buf);
    return out;
}

static NSString *primary_interface_name(void) {
    SCDynamicStoreRef store = SCDynamicStoreCreate(NULL, CFSTR("MiransasNet"), NULL, NULL);
    if (!store) return nil;
    CFPropertyListRef v = SCDynamicStoreCopyValue(store, CFSTR("State:/Network/Global/IPv4"));
    CFRelease(store);
    if (!v) return nil;
    NSString *name = nil;
    if (CFGetTypeID(v) == CFDictionaryGetTypeID()) {
        NSDictionary *dict = (NSDictionary *)v;
        id obj = [dict objectForKey:@"PrimaryInterface"];
        if ([obj isKindOfClass:[NSString class]]) {
            name = [[obj copy] autorelease];
        }
    }
    CFRelease(v);
    return name;
}

static NSString *ipv4_for_interface(NSString *iface) {
    if (!iface) return nil;
    const char *target = [iface UTF8String];
    struct ifaddrs *list = NULL;
    if (getifaddrs(&list) != 0 || !list) return nil;
    NSString *out = nil;
    for (struct ifaddrs *p = list; p; p = p->ifa_next) {
        if (!p->ifa_addr || !p->ifa_name) continue;
        if (p->ifa_addr->sa_family != AF_INET) continue;
        if (strcmp(p->ifa_name, target) != 0) continue;
        char addr[INET_ADDRSTRLEN];
        struct sockaddr_in *sin = (struct sockaddr_in *)p->ifa_addr;
        if (inet_ntop(AF_INET, &sin->sin_addr, addr, sizeof(addr))) {
            out = [NSString stringWithUTF8String:addr];
        }
        break;
    }
    freeifaddrs(list);
    return out;
}

static NSString *format_rate_kbs(double kbs) {
    if (kbs >= 1024.0) {
        return [NSString stringWithFormat:@"%.2f MB/s", kbs / 1024.0];
    }
    return [NSString stringWithFormat:@"%.1f KB/s", kbs];
}

static NSString *format_bytes_compact(uint64_t b) {
    return [NSByteCountFormatter stringFromByteCount:(long long)b
                                          countStyle:NSByteCountFormatterCountStyleFile];
}

static NSString *rssi_quality_label(NSInteger rssi) {
    if (rssi == 0) return @"";
    if (rssi >= -50) return @"Excellent";
    if (rssi >= -60) return @"Good";
    if (rssi >= -70) return @"Fair";
    return @"Weak";
}

static NSColor *rssi_color(NSInteger rssi) {
    if (rssi == 0) return [NSColor secondaryLabelColor];
    if (rssi >= -60) return [NSColor systemGreenColor];
    if (rssi >= -70) return [NSColor systemOrangeColor];
    return [NSColor systemRedColor];
}

#pragma mark - Sampler

@implementation MiransasNetworkSampler {
    BOOL _haveLast;
    net_counters_t _last;
    NSTimeInterval _lastTime;

    double _rxRateKBs;
    double _txRateKBs;
    uint64_t _sessionRx;
    uint64_t _sessionTx;

    NSString *_primaryIface;
    NSString *_primaryIP;
    BOOL _wifiPresent;
    BOOL _wifiPowerOn;
    BOOL _wifiAssociated;
    NSString *_ssid;
    NSInteger _rssi;
}

+ (instancetype)shared {
    static MiransasNetworkSampler *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [[MiransasNetworkSampler alloc] init];
    });
    return s;
}

- (void)dealloc {
    [_primaryIface release];
    [_primaryIP release];
    [_ssid release];
    [super dealloc];
}

- (void)sample {
    net_counters_t now = read_counters();
    NSTimeInterval t = [NSDate timeIntervalSinceReferenceDate];

    if (_haveLast) {
        NSTimeInterval dt = t - _lastTime;
        if (dt < 0.1) dt = 0.1;
        uint64_t dRx = (now.rx_bytes >= _last.rx_bytes) ? (now.rx_bytes - _last.rx_bytes) : 0;
        uint64_t dTx = (now.tx_bytes >= _last.tx_bytes) ? (now.tx_bytes - _last.tx_bytes) : 0;
        _rxRateKBs = (double)dRx / dt / 1024.0;
        _txRateKBs = (double)dTx / dt / 1024.0;
        _sessionRx += dRx;
        _sessionTx += dTx;
    } else {
        _haveLast = YES;
    }
    _last = now;
    _lastTime = t;

    NSString *iface = primary_interface_name();
    [_primaryIface release];
    _primaryIface = [iface retain];

    NSString *ip = iface ? ipv4_for_interface(iface) : nil;
    [_primaryIP release];
    _primaryIP = [ip retain];

    _wifiPresent = NO;
    _wifiPowerOn = NO;
    _wifiAssociated = NO;
    [_ssid release];
    _ssid = nil;
    _rssi = 0;

    CWInterface *cw = [[CWWiFiClient sharedWiFiClient] interface];
    if (cw) {
        _wifiPresent = YES;
        _wifiPowerOn = [cw powerOn];
        NSString *ssid = [cw ssid];
        if (ssid.length > 0) {
            _ssid = [ssid copy];
        }
        _rssi = [cw rssiValue];
        // SSID/BSSID need Location Services on macOS 14+, but rssi,
        // channel, and transmitRate are still readable. Use those to
        // detect association even when SSID is hidden.
        CWChannel *channel = [cw wlanChannel];
        double txRate = [cw transmitRate];
        _wifiAssociated = _wifiPowerOn &&
                          (_ssid != nil || _rssi != 0 || channel != nil || txRate > 0.0);
    }
}

- (double)rxRateKBs        { return _rxRateKBs; }
- (double)txRateKBs        { return _txRateKBs; }
- (uint64_t)sessionRxBytes { return _sessionRx; }
- (uint64_t)sessionTxBytes { return _sessionTx; }
- (NSString *)primaryInterface { return _primaryIface; }
- (NSString *)primaryIPv4      { return _primaryIP; }
- (BOOL)wifiPresent    { return _wifiPresent; }
- (BOOL)wifiPowerOn    { return _wifiPowerOn; }
- (BOOL)wifiAssociated { return _wifiAssociated; }
- (NSString *)wifiSSID { return _ssid; }
- (NSInteger)wifiRSSI  { return _rssi; }

@end

#pragma mark - Card view

@interface MiransasNetCard : NSView
@property(nonatomic, copy)   NSString *cardTitle;
@property(nonatomic, copy)   NSString *rxText;
@property(nonatomic, copy)   NSString *txText;
@end

@implementation MiransasNetCard {
    NSTextField *_titleField;
    NSTextField *_rxArrow;
    NSTextField *_rxValue;
    NSTextField *_txArrow;
    NSTextField *_txValue;
}

static NSTextField *net_label(NSView *parent, CGFloat size, NSFontWeight weight,
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

    _titleField = net_label(self, 11.0, NSFontWeightSemibold,
                            [NSColor secondaryLabelColor], NSTextAlignmentLeft);

    _rxArrow = net_label(self, 18.0, NSFontWeightSemibold,
                         [NSColor systemGreenColor], NSTextAlignmentCenter);
    [_rxArrow setStringValue:@"↓"];
    _rxValue = net_label(self, 18.0, NSFontWeightSemibold,
                         [NSColor labelColor], NSTextAlignmentLeft);
    [_rxValue setFont:[NSFont monospacedDigitSystemFontOfSize:18.0
                                                       weight:NSFontWeightSemibold]];

    _txArrow = net_label(self, 18.0, NSFontWeightSemibold,
                         [NSColor systemBlueColor], NSTextAlignmentCenter);
    [_txArrow setStringValue:@"↑"];
    _txValue = net_label(self, 18.0, NSFontWeightSemibold,
                         [NSColor labelColor], NSTextAlignmentLeft);
    [_txValue setFont:[NSFont monospacedDigitSystemFontOfSize:18.0
                                                       weight:NSFontWeightSemibold]];

    return self;
}

- (void)setCardTitle:(NSString *)cardTitle {
    [_cardTitle release];
    _cardTitle = [cardTitle copy];
    _titleField.stringValue = cardTitle ?: @"";
}

- (void)setRxText:(NSString *)rxText {
    [_rxText release];
    _rxText = [rxText copy];
    _rxValue.stringValue = rxText ?: @"";
}

- (void)setTxText:(NSString *)txText {
    [_txText release];
    _txText = [txText copy];
    _txValue.stringValue = txText ?: @"";
}

- (void)dealloc {
    [_cardTitle release];
    [_rxText release];
    [_txText release];
    [super dealloc];
}

- (void)layout {
    [super layout];
    NSRect b = self.bounds;
    CGFloat pad = 14.0;
    CGFloat arrowW = 22.0;

    _titleField.frame = NSMakeRect(pad, b.size.height - pad - 14.0,
                                   b.size.width - 2 * pad, 14.0);

    CGFloat rowH = 22.0;
    CGFloat rowGap = 6.0;
    CGFloat valueY = (b.size.height - 14.0 - 2 * rowH - rowGap) / 2.0 - 2.0;
    if (valueY < pad) valueY = pad;

    CGFloat rxY = valueY + rowH + rowGap;
    _rxArrow.frame = NSMakeRect(pad, rxY, arrowW, rowH);
    _rxValue.frame = NSMakeRect(pad + arrowW + 4.0, rxY,
                                b.size.width - pad * 2 - arrowW - 4.0, rowH);

    _txArrow.frame = NSMakeRect(pad, valueY, arrowW, rowH);
    _txValue.frame = NSMakeRect(pad + arrowW + 4.0, valueY,
                                b.size.width - pad * 2 - arrowW - 4.0, rowH);
}

@end

#pragma mark - Tab

@implementation MiransasNetworkTab {
    NSTextField *_titleField;

    MiransasNetCard *_rateCard;
    MiransasNetCard *_totalsCard;

    NSTextField *_ifaceHeader;
    NSImageView *_ifaceIcon;
    NSTextField *_ifaceName;
    NSTextField *_ifaceIP;

    NSTextField *_wifiHeader;
    NSImageView *_wifiIcon;
    NSTextField *_wifiSSIDField;
    NSTextField *_wifiRSSIField;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (!self) return nil;
    self.wantsLayer = YES;
    self.layer.backgroundColor = [[NSColor windowBackgroundColor] CGColor];

    _titleField = net_label(self, 12.0, NSFontWeightSemibold,
                            [NSColor systemTealColor], NSTextAlignmentLeft);
    [_titleField setStringValue:@"NETWORK"];

    _rateCard = [[MiransasNetCard alloc] initWithFrame:NSZeroRect];
    [_rateCard setCardTitle:@"CURRENT RATE"];
    [_rateCard setRxText:@"—"];
    [_rateCard setTxText:@"—"];
    [self addSubview:_rateCard];

    _totalsCard = [[MiransasNetCard alloc] initWithFrame:NSZeroRect];
    [_totalsCard setCardTitle:@"SESSION TOTAL"];
    [_totalsCard setRxText:@"0 bytes"];
    [_totalsCard setTxText:@"0 bytes"];
    [self addSubview:_totalsCard];

    _ifaceHeader = net_label(self, 11.0, NSFontWeightSemibold,
                             [NSColor secondaryLabelColor], NSTextAlignmentLeft);
    [_ifaceHeader setStringValue:@"INTERFACE"];

    _ifaceIcon = [[NSImageView alloc] init];
    [_ifaceIcon setImageScaling:NSImageScaleProportionallyUpOrDown];
    if (@available(macOS 11.0, *)) {
        _ifaceIcon.image = [NSImage imageWithSystemSymbolName:@"network"
                                     accessibilityDescription:nil];
        _ifaceIcon.contentTintColor = [NSColor systemTealColor];
    }
    [self addSubview:_ifaceIcon];

    _ifaceName = net_label(self, 14.0, NSFontWeightMedium,
                           [NSColor labelColor], NSTextAlignmentLeft);
    [_ifaceName setStringValue:@"—"];

    _ifaceIP = net_label(self, 13.0, NSFontWeightRegular,
                         [NSColor secondaryLabelColor], NSTextAlignmentRight);
    [_ifaceIP setFont:[NSFont monospacedDigitSystemFontOfSize:13.0
                                                       weight:NSFontWeightRegular]];
    [_ifaceIP setStringValue:@""];

    _wifiHeader = net_label(self, 11.0, NSFontWeightSemibold,
                            [NSColor secondaryLabelColor], NSTextAlignmentLeft);
    [_wifiHeader setStringValue:@"WI-FI"];

    _wifiIcon = [[NSImageView alloc] init];
    [_wifiIcon setImageScaling:NSImageScaleProportionallyUpOrDown];
    if (@available(macOS 11.0, *)) {
        _wifiIcon.image = [NSImage imageWithSystemSymbolName:@"wifi"
                                    accessibilityDescription:nil];
        _wifiIcon.contentTintColor = [NSColor systemBlueColor];
    }
    [self addSubview:_wifiIcon];

    _wifiSSIDField = net_label(self, 14.0, NSFontWeightMedium,
                               [NSColor labelColor], NSTextAlignmentLeft);
    [_wifiSSIDField setStringValue:@"—"];
    [[_wifiSSIDField cell] setLineBreakMode:NSLineBreakByTruncatingTail];

    _wifiRSSIField = net_label(self, 13.0, NSFontWeightRegular,
                               [NSColor secondaryLabelColor], NSTextAlignmentRight);
    [_wifiRSSIField setStringValue:@""];

    return self;
}

- (void)dealloc {
    [_rateCard release];
    [_totalsCard release];
    [_ifaceIcon release];
    [_wifiIcon release];
    [super dealloc];
}

- (void)layout {
    [super layout];
    NSRect b = self.bounds;
    CGFloat pad = 24.0;
    CGFloat innerW = b.size.width - 2.0 * pad;

    CGFloat titleH = 16.0;
    CGFloat cardH = 96.0;
    CGFloat sectionHeaderH = 14.0;
    CGFloat rowH = 22.0;
    CGFloat iconW = 22.0;

    CGFloat y = b.size.height - pad;

    y -= titleH;
    _titleField.frame = NSMakeRect(pad, y, innerW, titleH);

    y -= 12.0 + cardH;
    CGFloat cardGap = 12.0;
    CGFloat cardW = (innerW - cardGap) / 2.0;
    _rateCard.frame   = NSMakeRect(pad, y, cardW, cardH);
    _totalsCard.frame = NSMakeRect(pad + cardW + cardGap, y, cardW, cardH);

    y -= 22.0 + sectionHeaderH;
    _ifaceHeader.frame = NSMakeRect(pad, y, innerW, sectionHeaderH);

    y -= 6.0 + rowH;
    _ifaceIcon.frame = NSMakeRect(pad, y - 1.0, iconW, rowH);
    CGFloat ifaceNameX = pad + iconW + 8.0;
    CGFloat ipW = 180.0;
    _ifaceName.frame = NSMakeRect(ifaceNameX, y, innerW - iconW - 8.0 - ipW - 8.0, rowH);
    _ifaceIP.frame   = NSMakeRect(pad + innerW - ipW, y, ipW, rowH);

    y -= 18.0 + sectionHeaderH;
    _wifiHeader.frame = NSMakeRect(pad, y, innerW, sectionHeaderH);

    y -= 6.0 + rowH;
    _wifiIcon.frame = NSMakeRect(pad, y - 1.0, iconW, rowH);
    CGFloat ssidX = pad + iconW + 8.0;
    CGFloat rssiW = 200.0;
    _wifiSSIDField.frame = NSMakeRect(ssidX, y, innerW - iconW - 8.0 - rssiW - 8.0, rowH);
    _wifiRSSIField.frame = NSMakeRect(pad + innerW - rssiW, y, rssiW, rowH);
}

- (void)updateWithSnapshot:(const agent_snapshot_t *)snapshot {
    (void)snapshot;
    MiransasNetworkSampler *s = [MiransasNetworkSampler shared];

    [_rateCard setRxText:format_rate_kbs([s rxRateKBs])];
    [_rateCard setTxText:format_rate_kbs([s txRateKBs])];

    [_totalsCard setRxText:format_bytes_compact([s sessionRxBytes])];
    [_totalsCard setTxText:format_bytes_compact([s sessionTxBytes])];

    NSString *iface = [s primaryInterface];
    NSString *ip = [s primaryIPv4];
    [_ifaceName setStringValue:iface.length ? iface : @"(no active interface)"];
    [_ifaceIP setStringValue:ip.length ? ip : @""];

    if (![s wifiPresent]) {
        [_wifiSSIDField setStringValue:@"(no Wi-Fi adapter)"];
        [_wifiRSSIField setStringValue:@""];
        _wifiRSSIField.textColor = [NSColor secondaryLabelColor];
        _wifiIcon.contentTintColor = [NSColor tertiaryLabelColor];
    } else if (![s wifiPowerOn]) {
        [_wifiSSIDField setStringValue:@"Off"];
        [_wifiRSSIField setStringValue:@""];
        _wifiRSSIField.textColor = [NSColor secondaryLabelColor];
        _wifiIcon.contentTintColor = [NSColor tertiaryLabelColor];
    } else if (![s wifiAssociated]) {
        [_wifiSSIDField setStringValue:@"Not connected"];
        [_wifiRSSIField setStringValue:@""];
        _wifiRSSIField.textColor = [NSColor secondaryLabelColor];
        _wifiIcon.contentTintColor = [NSColor tertiaryLabelColor];
    } else {
        NSString *ssid = [s wifiSSID];
        NSInteger rssi = [s wifiRSSI];
        NSString *leftText = ssid.length
            ? ssid
            : @"Wi-Fi (SSID hidden — Location Services not granted)";
        [_wifiSSIDField setStringValue:leftText];
        _wifiIcon.contentTintColor = rssi_color(rssi);
        if (rssi == 0) {
            [_wifiRSSIField setStringValue:@""];
            _wifiRSSIField.textColor = [NSColor secondaryLabelColor];
        } else {
            [_wifiRSSIField setStringValue:
                [NSString stringWithFormat:@"%@   %ld dBm",
                                           rssi_quality_label(rssi), (long)rssi]];
            _wifiRSSIField.textColor = rssi_color(rssi);
        }
    }
}

@end
