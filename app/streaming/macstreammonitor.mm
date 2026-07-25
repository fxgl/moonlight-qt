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
    NSTextField* bitrateLabel;
    NSTextField* resolutionLabel;
    NSTextField* countdownLabel;
    NSButton* increaseButton;
    NSButton* decreaseButton;
    NSPopUpButton* displayPopup;
    MLStreamGraphView* graph;
    NSMenuItem* rootMenuItem;
}
- (instancetype)initWithActions:(MacStreamMonitor::Actions)callbacks;
- (void)showWindow:(id)sender;
- (void)increaseQuality:(id)sender;
- (void)decreaseQuality:(id)sender;
- (void)refreshDisplays:(id)sender;
- (void)switchDisplay:(id)sender;
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

    window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 640, 480)
                                         styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                   NSWindowStyleMaskMiniaturizable
                                           backing:NSBackingStoreBuffered
                                             defer:NO];
    [window setTitle:@"Moonlight Connection Monitor"];
    [window center];
    [window setReleasedWhenClosed:NO];
    NSView* content = [window contentView];

    speedLabel = makeLabel(NSMakeRect(20, 435, 190, 24), 15);
    lossLabel = makeLabel(NSMakeRect(220, 435, 180, 24), 15);
    bitrateLabel = makeLabel(NSMakeRect(410, 435, 210, 24), 15);
    resolutionLabel = makeLabel(NSMakeRect(20, 405, 240, 24), 15);
    countdownLabel = makeLabel(NSMakeRect(270, 405, 350, 24), 15);
    [content addSubview:speedLabel];
    [content addSubview:lossLabel];
    [content addSubview:bitrateLabel];
    [content addSubview:resolutionLabel];
    [content addSubview:countdownLabel];

    graph = [[MLStreamGraphView alloc] initWithFrame:NSMakeRect(20, 145, 600, 245)];
    [graph setWantsLayer:YES];
    [graph.layer setCornerRadius:6.0];
    [content addSubview:graph];

    NSTextField* legend = makeLabel(NSMakeRect(20, 118, 600, 20), 12);
    [legend setStringValue:@"Green: throughput     Blue: target bitrate     Red: packet loss"];
    [content addSubview:legend];
    [legend release];

    decreaseButton = [makeButton(@"− Quality", NSMakeRect(20, 72, 105, 32), self, @selector(decreaseQuality:)) retain];
    increaseButton = [makeButton(@"+ Quality", NSMakeRect(135, 72, 105, 32), self, @selector(increaseQuality:)) retain];
    [content addSubview:decreaseButton];
    [content addSubview:increaseButton];

    displayPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(255, 72, 260, 32) pullsDown:NO];
    [displayPopup setTarget:self];
    [displayPopup setAction:@selector(switchDisplay:)];
    [content addSubview:displayPopup];
    [content addSubview:makeButton(@"Refresh", NSMakeRect(525, 72, 95, 32), self, @selector(refreshDisplays:))];

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
    [bitrateLabel release];
    [resolutionLabel release];
    [countdownLabel release];
    [increaseButton release];
    [decreaseButton release];
    [displayPopup release];
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
    if (index >= 0 && actions.switchDisplay) actions.switchDisplay(static_cast<int>(index));
}

- (void)update:(const StreamMonitorModel::Snapshot&)snapshot
{
    [speedLabel setStringValue:[NSString stringWithFormat:@"Speed %.2f Mbps", snapshot.throughputMbps]];
    [lossLabel setStringValue:[NSString stringWithFormat:@"Loss %.2f%%", snapshot.packetLossPercent]];
    [bitrateLabel setStringValue:[NSString stringWithFormat:@"Bitrate %.2f Mbps", snapshot.targetBitrateKbps / 1000.0]];
    [resolutionLabel setStringValue:[NSString stringWithFormat:@"Resolution %d × %d", snapshot.width, snapshot.height]];
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
    [displayPopup setEnabled:[displayPopup numberOfItems] > 0];
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
