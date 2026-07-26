#pragma once

#include <QByteArray>

#include <Limelight.h>

namespace KeyboardLayout {

struct Descriptor
{
    unsigned char platform = LI_KEYBOARD_LAYOUT_PLATFORM_UNKNOWN;
    QByteArray language;
    QByteArray layoutId;

    bool isValid() const;
};

Descriptor current();
bool needsSync(const Descriptor& currentLayout, const Descriptor& lastSentLayout, bool force);

} // namespace KeyboardLayout
