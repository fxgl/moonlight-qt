#pragma once

#include <Limelight.h>

class KeyboardShortcutTranslator
{
public:
    // Moonlight's keyboard protocol uses Windows virtual-key codes on every
    // client platform. Sunshine maps VK_LWIN/VK_RWIN to Command on macOS.
    // Swapping those keys with Control therefore translates the primary
    // shortcut modifier in either direction between macOS and Windows.
    static void translate(short& keyCode, char& modifiers)
    {
        switch (keyCode) {
        case 0x5B: // VK_LWIN / left Command on a macOS host
            keyCode = 0xA2; // VK_LCONTROL
            break;
        case 0x5C: // VK_RWIN / right Command on a macOS host
            keyCode = 0xA3; // VK_RCONTROL
            break;
        case 0xA2: // VK_LCONTROL
            keyCode = 0x5B; // VK_LWIN / left Command on a macOS host
            break;
        case 0xA3: // VK_RCONTROL
            keyCode = 0x5C; // VK_RWIN / right Command on a macOS host
            break;
        default:
            break;
        }

        const bool control = (modifiers & MODIFIER_CTRL) != 0;
        const bool meta = (modifiers & MODIFIER_META) != 0;
        modifiers &= ~(MODIFIER_CTRL | MODIFIER_META);
        if (control) {
            modifiers |= MODIFIER_META;
        }
        if (meta) {
            modifiers |= MODIFIER_CTRL;
        }
    }
};
