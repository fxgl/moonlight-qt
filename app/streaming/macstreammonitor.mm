#include "macstreammonitor.h"

#import <AppKit/AppKit.h>

#include <algorithm>
#include <cmath>
#include <utility>

@interface MLStreamGraphView : NSView {
@public
    std::vector<StreamMonitorModel::Sample> samples;
}
@end

@implementation MLStreamGraphView
- (BOOL)isFlipped { return YES; }

- (void)drawRect:(NSRect)dirtyRect
{
    [[NSColor colorWithWhite:0.08 alpha:1.0] setFill];
    NSRectFill(self.bounds);

    [[NSColor colorWithWhite:0.25 alpha:1.0] setStroke];
    for (int line = 1; line < 4; line++) {
        const CGFloat y = NSHeight(self.bounds) * line / 4.0;
        NSBezierPath* grid = [NSBezierPath bezierPath];
        [grid moveToPoint:NSMakePoint(0, y)];
        [grid lineToPoint:NSMakePoint(NSWidth(self.bounds), y)];
        [grid stroke];
    }

    if (samples.size() < 2) {
        return;
    }

    double maxMbps = 1.0;
    for (const auto& sample : samples) {
        maxMbps = std::max({maxMbps, sample.throughputMbps, sample.targetBitrateMbps});
    }
    const CGFloat step = NSWidth(self.bounds) / static_cast<CGFloat>(samples.size() - 1);
    auto drawSeries = [&](NSColor* color, auto value, double maximum) {
        NSBezierPath* path = [NSBezierPath bezierPath];
        [path setLineWidth:2.0];
        for (std::size_t i = 0; i < samples.size(); i++) {
            const CGFloat x = step * i;
            const CGFloat y = NSHeight(self.bounds) *
                    (1.0 - std::clamp(value(samples[i]) / maximum, 0.0, 1.0));
            if (i == 0) {
                [path moveToPoint:NSMakePoint(x, y)];
            }
            else {
                [path lineToPoint:NSMakePoint(x, y)];
            }
        }
        [color setStroke];
        [path stroke];
    };

    drawSeries([NSColor systemGreenColor], [](const auto& s) { return s.throughputMbps; }, maxMbps);
    drawSeries([NSColor systemBlueColor], [](const auto& s) { return s.targetBitrateMbps; }, maxMbps);
    drawSeries([NSColor systemRedColor], [](const auto& s) { return s.packetLossPercent; }, 100.0);
}
@end

@interface MLStreamMonitorController : NSObject {
@public
    MacStreamMonitor::Actions actions;
    NSWindow* window;
    NSTextField* speedLabel;
    NSTextField* lossLabel;
    NSTextField* fecLabel;
    NSTextField* droppedLabel;
    NSTextField* bitrateLabel;
    NSTextField* resolutionLabel;
    NSTextField* rttLabel;
    NSTextField* jitterLabel;
    NSTextField* latencyLabel;
    NSTextField* fpsLabel;
    NSTextField* hostLatencyLabel;
    NSTextField* clientLatencyLabel;
    NSTextField* countdownLabel;
    NSButton* increaseButton;
    NSButton* decreaseButton;
    NSButton* previousDisplayButton;
    NSButton* nextDisplayButton;
    NSButton* refreshDisplayButton;
    NSPopUpButton* displayPopup;
    NSTextField* displayStatusLabel;
    MLStreamGraphView* graph;
    NSMenuItem* rootMenuItem;
    NSInteger requestedDisplayIndex;
}
- (instancetype)initWithActions:(MacStreamMonitor::Actions)callbacks;
- (void)showWindow:(id)sender;
- (void)increaseQuality:(id)sender;
- (void)decreaseQuality:(id)sender;
- (void)refreshDisplays:(id)sender;
- (void)switchDisplay:(id)sender;
- (void)previousDisplay:(id)sender;
- (void)nextDisplay:(id)sender;
- (void)requestDisplayIndex:(NSInteger)index;
- (void)update:(const StreamMonitorModel::Snapshot&)snapshot;
@end

static NSTextField* makeLabel(NSRect frame, CGFloat size)
{
    NSTextField* label = [[NSTextField alloc] initWithFrame:frame];
    [label setBezeled:NO];
    [label setDrawsBackground:NO];
    [label setEditable:NO];
    [label setSelectable:NO];
    [label setFont:[NSFont monospacedDigitSystemFontOfSize:size weight:NSFontWeightRegular]];
    return label;
}

static NSButton* makeButton(NSString* title, NSRect frame, id target, SEL action)
{
    NSButton* button = [[NSButton alloc] initWithFrame:frame];
    [button setTitle:title];
    [button setBezelStyle:NSBezelStyleRounded];
    [button setTarget:target];
    [button setAction:action];
    return [button autorelease];
}

@implementation MLStreamMonitorController
- (instancetype)initWithActions:(MacStreamMonitor::Actions)callbacks
{
    self = [super init];
    if (!self) return nil;
    actions = std::move(callbacks);

    requestedDisplayIndex = -1;
    window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 720, 650)
                                         styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                   NSWindowStyleMaskMiniaturizable
                                           backing:NSBackingStoreBuffered
                                             defer:NO];
    [window setTitle:@"Moonlight Connection Monitor"];
    [window center];
    [window setReleasedWhenClosed:NO];
    NSView* content = [window contentView];

    speedLabel = makeLabel(NSMakeRect(20, 605, 215, 24), 15);
    bitrateLabel = makeLabel(NSMakeRect(250, 605, 215, 24), 15);
    resolutionLabel = makeLabel(NSMakeRect(480, 605, 220, 24), 15);
    lossLabel = makeLabel(NSMakeRect(20, 575, 215, 24), 14);
    fecLabel = makeLabel(NSMakeRect(250, 575, 215, 24), 14);
    droppedLabel = makeLabel(NSMakeRect(480, 575, 220, 24), 12);
    rttLabel = makeLabel(NSMakeRect(20, 545, 215, 24), 14);
    jitterLabel = makeLabel(NSMakeRect(250, 545, 215, 24), 14);
    latencyLabel = makeLabel(NSMakeRect(480, 545, 220, 24), 14);
    fpsLabel = makeLabel(NSMakeRect(20, 515, 215, 24), 13);
    hostLatencyLabel = makeLabel(NSMakeRect(250, 515, 215, 24), 13);
    clientLatencyLabel = makeLabel(NSMakeRect(480, 515, 220, 24), 11);
    countdownLabel = makeLabel(NSMakeRect(20, 480, 680, 24), 14);
    [content addSubview:speedLabel];
    [content addSubview:bitrateLabel];
    [content addSubview:resolutionLabel];
    [content addSubview:lossLabel];
    [content addSubview:fecLabel];
    [content addSubview:droppedLabel];
    [content addSubview:rttLabel];
    [content addSubview:jitterLabel];
    [content addSubview:latencyLabel];
    [content addSubview:fpsLabel];
    [content addSubview:hostLatencyLabel];
    [content addSubview:clientLatencyLabel];
    [content addSubview:countdownLabel];

    graph = [[MLStreamGraphView alloc] initWithFrame:NSMakeRect(20, 200, 680, 260)];
    [graph setWantsLayer:YES];
    [graph.layer setCornerRadius:6.0];
    [content addSubview:graph];

    NSTextField* legend = makeLabel(NSMakeRect(20, 173, 680, 20), 12);
    NSMutableAttributedString* legendText = [[[NSMutableAttributedString alloc]
        initWithString:@"● Throughput     ● Target bitrate     ● Packet loss"] autorelease];
    [legendText addAttribute:NSForegroundColorAttributeName value:[NSColor systemGreenColor] range:NSMakeRange(0, 1)];
    [legendText addAttribute:NSForegroundColorAttributeName value:[NSColor systemBlueColor] range:NSMakeRange(17, 1)];
    [legendText addAttribute:NSForegroundColorAttributeName value:[NSColor systemRedColor] range:NSMakeRange(38, 1)];
    [legend setAttributedStringValue:legendText];
    [content addSubview:legend];
    [legend release];

    NSTextField* qualityTitle = makeLabel(NSMakeRect(20, 145, 180, 18), 11);
    [qualityTitle setStringValue:@"STREAM QUALITY"];
    [qualityTitle setTextColor:[NSColor secondaryLabelColor]];
    [content addSubview:qualityTitle];
    [qualityTitle release];

    decreaseButton = [makeButton(@"− Quality", NSMakeRect(485, 132, 105, 32), self, @selector(decreaseQuality:)) retain];
    increaseButton = [makeButton(@"+ Quality", NSMakeRect(595, 132, 105, 32), self, @selector(increaseQuality:)) retain];
    [content addSubview:decreaseButton];
    [content addSubview:increaseButton];

    NSVisualEffectView* displayCard = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(20, 15, 680, 105)];
    [displayCard setMaterial:NSVisualEffectMaterialSidebar];
    [displayCard setBlendingMode:NSVisualEffectBlendingModeWithinWindow];
    [displayCard setState:NSVisualEffectStateActive];
    [displayCard setWantsLayer:YES];
    [displayCard.layer setCornerRadius:10.0];
    [content addSubview:displayCard];

    NSTextField* displayTitle = makeLabel(NSMakeRect(16, 76, 300, 18), 11);
    [displayTitle setStringValue:@"REMOTE DISPLAY"];
    [displayTitle setTextColor:[NSColor secondaryLabelColor]];
    [displayCard addSubview:displayTitle];
    [displayTitle release];

    displayPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(14, 37, 470, 32) pullsDown:NO];
    [displayPopup setFont:[NSFont systemFontOfSize:14 weight:NSFontWeightMedium]];
    [displayPopup setToolTip:@"Choose the display captured on the remote computer"];
    [displayPopup setAccessibilityLabel:@"Remote display"];
    [displayPopup setTarget:self];
    [displayPopup setAction:@selector(switchDisplay:)];
    [displayCard addSubview:displayPopup];

    previousDisplayButton = [makeButton(@"‹", NSMakeRect(494, 37, 42, 32), self, @selector(previousDisplay:)) retain];
    nextDisplayButton = [makeButton(@"›", NSMakeRect(540, 37, 42, 32), self, @selector(nextDisplay:)) retain];
    refreshDisplayButton = [makeButton(@"Refresh", NSMakeRect(590, 37, 76, 32), self, @selector(refreshDisplays:)) retain];
    [previousDisplayButton setToolTip:@"Previous remote display"];
    [nextDisplayButton setToolTip:@"Next remote display"];
    [refreshDisplayButton setToolTip:@"Refresh remote displays"];
    [displayCard addSubview:previousDisplayButton];
    [displayCard addSubview:nextDisplayButton];
    [displayCard addSubview:refreshDisplayButton];

    displayStatusLabel = makeLabel(NSMakeRect(16, 11, 650, 18), 11);
    [displayStatusLabel setTextColor:[NSColor secondaryLabelColor]];
    [displayStatusLabel setStringValue:@"Waiting for display information…"];
    [displayCard addSubview:displayStatusLabel];
    [displayCard release];

    NSMenu* streamMenu = [[NSMenu alloc] initWithTitle:@"Stream"];
    NSMenuItem* monitorItem = [[NSMenuItem alloc] initWithTitle:@"Connection Monitor…"
                                                        action:@selector(showWindow:)
                                                 keyEquivalent:@"m"];
    [monitorItem setKeyEquivalentModifierMask:NSEventModifierFlagCommand | NSEventModifierFlagShift];
    [monitorItem setTarget:self];
    [streamMenu addItem:monitorItem];
    [monitorItem release];
    rootMenuItem = [[NSMenuItem alloc] initWithTitle:@"Stream" action:nil keyEquivalent:@""];
    [rootMenuItem setSubmenu:streamMenu];
    [streamMenu release];
    [[NSApp mainMenu] addItem:rootMenuItem];
    return self;
}

- (void)dealloc
{
    [[NSApp mainMenu] removeItem:rootMenuItem];
    [rootMenuItem release];
    [speedLabel release];
    [lossLabel release];
    [fecLabel release];
    [droppedLabel release];
    [bitrateLabel release];
    [resolutionLabel release];
    [rttLabel release];
    [jitterLabel release];
    [latencyLabel release];
    [fpsLabel release];
    [hostLatencyLabel release];
    [clientLatencyLabel release];
    [countdownLabel release];
    [increaseButton release];
    [decreaseButton release];
    [previousDisplayButton release];
    [nextDisplayButton release];
    [refreshDisplayButton release];
    [displayPopup release];
    [displayStatusLabel release];
    [graph release];
    [window close];
    [window release];
    [super dealloc];
}

- (void)showWindow:(id)sender { [window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES]; }
- (void)increaseQuality:(id)sender { if (actions.increaseQuality) actions.increaseQuality(); }
- (void)decreaseQuality:(id)sender { if (actions.decreaseQuality) actions.decreaseQuality(); }
- (void)refreshDisplays:(id)sender { if (actions.refreshDisplays) actions.refreshDisplays(); }
- (void)switchDisplay:(id)sender {
    const NSInteger index = [displayPopup indexOfSelectedItem];
    [self requestDisplayIndex:index];
}
- (void)previousDisplay:(id)sender {
    const NSInteger count = [displayPopup numberOfItems];
    if (count > 1) [self requestDisplayIndex:([displayPopup indexOfSelectedItem] - 1 + count) % count];
}
- (void)nextDisplay:(id)sender {
    const NSInteger count = [displayPopup numberOfItems];
    if (count > 1) [self requestDisplayIndex:([displayPopup indexOfSelectedItem] + 1) % count];
}
- (void)requestDisplayIndex:(NSInteger)index {
    if (index < 0 || index >= [displayPopup numberOfItems]) return;
    [displayPopup selectItemAtIndex:index];
    requestedDisplayIndex = index;
    [displayStatusLabel setStringValue:[NSString stringWithFormat:@"Switching to display %ld…", index + 1]];
    if (actions.switchDisplay) actions.switchDisplay(static_cast<int>(index));
}

- (void)update:(const StreamMonitorModel::Snapshot&)snapshot
{
    [speedLabel setStringValue:[NSString stringWithFormat:@"Speed %.2f Mbps", snapshot.throughputMbps]];
    [lossLabel setStringValue:[NSString stringWithFormat:@"Loss %.2f%%", snapshot.packetLossPercent]];
    [fecLabel setStringValue:[NSString stringWithFormat:@"FEC recovered %llu/s",
                                                        static_cast<unsigned long long>(snapshot.fecRecoveredPackets)]];
    [droppedLabel setStringValue:[NSString stringWithFormat:@"Frame drop %.2f%% · pacer %.2f%%",
                                                            snapshot.networkDroppedFramePercent,
                                                            snapshot.pacerDroppedFramePercent]];
    [bitrateLabel setStringValue:[NSString stringWithFormat:@"Bitrate %.2f Mbps", snapshot.targetBitrateKbps / 1000.0]];
    [resolutionLabel setStringValue:[NSString stringWithFormat:@"Resolution %d × %d", snapshot.width, snapshot.height]];
    [rttLabel setStringValue:[NSString stringWithFormat:@"RTT %.1f ms", snapshot.rttMs]];
    [jitterLabel setStringValue:[NSString stringWithFormat:@"RTT jitter %.1f ms", snapshot.networkJitterMs]];
    [latencyLabel setStringValue:[NSString stringWithFormat:@"Est. lag %.1f ms", snapshot.estimatedLatencyMs]];
    [fpsLabel setStringValue:[NSString stringWithFormat:@"FPS %.1f / %.1f / %.1f",
                                                     snapshot.receivedFps,
                                                     snapshot.decodedFps,
                                                     snapshot.renderedFps]];
    [hostLatencyLabel setStringValue:[NSString stringWithFormat:@"Host %.1f ms", snapshot.hostLatencyMs]];
    [clientLatencyLabel setStringValue:[NSString stringWithFormat:@"Decode %.1f · Pace %.1f · Render %.1f ms",
                                                               snapshot.decodeLatencyMs,
                                                               snapshot.pacerLatencyMs,
                                                               snapshot.renderLatencyMs]];
    if (!snapshot.adaptiveQualityEnabled) {
        [countdownLabel setStringValue:@"Automatic scaling disabled"];
    }
    else if (!snapshot.canIncreaseQuality) {
        [countdownLabel setStringValue:@"Automatic scaling: maximum quality"];
    }
    else {
        [countdownLabel setStringValue:[NSString stringWithFormat:@"Next auto scale in %d s", snapshot.secondsUntilAutoScale]];
    }
    [increaseButton setEnabled:snapshot.canIncreaseQuality];
    [decreaseButton setEnabled:snapshot.canDecreaseQuality];

    graph->samples = snapshot.history;
    [graph setNeedsDisplay:YES];

    const NSInteger oldSelection = [displayPopup indexOfSelectedItem];
    bool changed = static_cast<std::size_t>([displayPopup numberOfItems]) != snapshot.displays.size();
    if (!changed) {
        for (std::size_t i = 0; i < snapshot.displays.size(); i++) {
            NSString* name = [NSString stringWithUTF8String:snapshot.displays[i].c_str()];
            if (![[displayPopup itemTitleAtIndex:i] isEqualToString:name]) { changed = true; break; }
        }
    }
    if (changed) {
        [displayPopup removeAllItems];
        for (const auto& display : snapshot.displays) {
            NSString* name = [NSString stringWithUTF8String:display.c_str()];
            [displayPopup addItemWithTitle:name ?: @"Display"];
        }
    }
    const int selected = snapshot.currentDisplay >= 0 ? snapshot.currentDisplay : static_cast<int>(oldSelection);
    if (selected >= 0 && selected < [displayPopup numberOfItems]) {
        [displayPopup selectItemAtIndex:selected];
    }
    const NSInteger displayCount = [displayPopup numberOfItems];
    const bool hasDisplays = displayCount > 0;
    const bool canCycle = displayCount > 1;
    if (requestedDisplayIndex >= displayCount) {
        requestedDisplayIndex = -1;
    }
    if (requestedDisplayIndex >= 0 && snapshot.currentDisplay == requestedDisplayIndex) {
        requestedDisplayIndex = -1;
    }
    if (!hasDisplays) {
        [displayStatusLabel setStringValue:@"Live display switching is unavailable on this host"];
    }
    else if (requestedDisplayIndex >= 0) {
        [displayStatusLabel setStringValue:[NSString stringWithFormat:@"Switching to display %ld…", requestedDisplayIndex + 1]];
    }
    else {
        const NSInteger active = [displayPopup indexOfSelectedItem];
        if (active >= 0) {
            [displayStatusLabel setStringValue:[NSString stringWithFormat:@"Display %ld of %ld · Video and pointer are linked",
                                                                          active + 1, displayCount]];
        }
        else {
            [displayStatusLabel setStringValue:@"Choose the remote display to stream and control"];
        }
    }
    [displayPopup setEnabled:hasDisplays];
    [previousDisplayButton setEnabled:canCycle];
    [nextDisplayButton setEnabled:canCycle];
    [refreshDisplayButton setEnabled:true];
}
@end

class MacStreamMonitor::Impl
{
public:
    explicit Impl(Actions actions)
        : controller([[MLStreamMonitorController alloc] initWithActions:std::move(actions)])
    {
    }

    ~Impl() { [controller release]; }

    MLStreamMonitorController* controller;
};

MacStreamMonitor::MacStreamMonitor(Actions actions)
    : m_Impl(std::make_unique<Impl>(std::move(actions)))
{
}

MacStreamMonitor::~MacStreamMonitor() = default;

void MacStreamMonitor::update(const StreamMonitorModel::Snapshot& snapshot)
{
    [m_Impl->controller update:snapshot];
}
