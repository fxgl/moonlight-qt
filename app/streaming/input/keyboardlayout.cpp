#include "keyboardlayout.h"

#include <QtGlobal>

bool KeyboardLayout::Descriptor::isValid() const
{
    return platform != LI_KEYBOARD_LAYOUT_PLATFORM_UNKNOWN && !language.isEmpty();
}

bool KeyboardLayout::needsSync(const Descriptor& currentLayout, const Descriptor& lastSentLayout, bool force)
{
    return currentLayout.isValid() &&
           (force || currentLayout.platform != lastSentLayout.platform ||
            currentLayout.language != lastSentLayout.language || currentLayout.layoutId != lastSentLayout.layoutId);
}

#if !defined(Q_OS_DARWIN) && !defined(Q_OS_WIN)
KeyboardLayout::Descriptor KeyboardLayout::current() { return {}; }
#endif
