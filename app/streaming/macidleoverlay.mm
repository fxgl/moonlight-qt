#include "macidleoverlay.h"

#include "SDL_compat.h"
#include <SDL_syswm.h>

#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

class MacIdleOverlay::Impl
{
public:
    explicit Impl(SDL_Window* window)
        : sdlWindow(window)
    {
    }

    ~Impl()
    {
        @autoreleasepool {
            [effectView removeFromSuperview];
            [effectView release];
        }
    }

    void setVisible(bool visible)
    {
        @autoreleasepool {
            if (!visible) {
                [effectView setHidden:YES];
                return;
            }

            SDL_SysWMinfo info;
            SDL_VERSION(&info.version);
            if (!SDL_GetWindowWMInfo(sdlWindow, &info) || info.subsystem != SDL_SYSWM_COCOA) {
                SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                            "Unable to attach inactive stream blur: %s",
                            SDL_GetError());
                return;
            }

            NSView* contentView = [info.info.cocoa.window contentView];
            if (effectView == nil) {
                effectView = [[NSVisualEffectView alloc] initWithFrame:[contentView bounds]];
                [effectView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
                [effectView setMaterial:NSVisualEffectMaterialFullScreenUI];
                [effectView setBlendingMode:NSVisualEffectBlendingModeWithinWindow];
                [effectView setState:NSVisualEffectStateActive];
                [effectView setWantsLayer:YES];

                NSView* dimmer = [[NSView alloc] initWithFrame:[effectView bounds]];
                [dimmer setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
                [dimmer setWantsLayer:YES];
                [[dimmer layer] setBackgroundColor:[[NSColor colorWithWhite:0.0 alpha:0.42] CGColor]];
                [effectView addSubview:dimmer];
                [dimmer release];
            }

            if ([effectView superview] != contentView) {
                [effectView removeFromSuperview];
            }
            [contentView addSubview:effectView positioned:NSWindowAbove relativeTo:nil];
            [effectView setFrame:[contentView bounds]];
            [effectView setHidden:NO];
        }
    }

private:
    SDL_Window* sdlWindow;
    NSVisualEffectView* effectView = nil;
};

MacIdleOverlay::MacIdleOverlay(SDL_Window* window)
    : m_Impl(std::make_unique<Impl>(window))
{
}

MacIdleOverlay::~MacIdleOverlay() = default;

void MacIdleOverlay::setVisible(bool visible)
{
    m_Impl->setVisible(visible);
}
