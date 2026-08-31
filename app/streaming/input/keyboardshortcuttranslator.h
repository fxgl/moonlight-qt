#pragma once

#include <Limelight.h>
#include <QString>

class KeyboardShortcutTranslator
{
public:
    enum class OperatingSystem {
        Unknown,
        Windows,
        MacOS,
    };

    static OperatingSystem operatingSystemFromPlatform(const QString& platform)
    {
        if (platform.compare(QStringLiteral("windows"), Qt::CaseInsensitive) == 0) {
            return OperatingSystem::Windows;
        }
        if (platform.compare(QStringLiteral("macos"), Qt::CaseInsensitive) == 0 ||
                platform.compare(QStringLiteral("osx"), Qt::CaseInsensitive) == 0) {
            return OperatingSystem::MacOS;
        }
        return OperatingSystem::Unknown;
    }

    static bool shouldTranslate(OperatingSystem client, OperatingSystem host)
    {
        return (client == OperatingSystem::MacOS && host == OperatingSystem::Windows) ||
               (client == OperatingSystem::Windows && host == OperatingSystem::MacOS);
    }

    static bool shouldTranslate(const QString& hostPlatform)
    {
#ifdef Q_OS_DARWIN
        constexpr OperatingSystem client = OperatingSystem::MacOS;
#elif defined(Q_OS_WIN)
        constexpr OperatingSystem client = OperatingSystem::Windows;
#else
        constexpr OperatingSystem client = OperatingSystem::Unknown;
#endif
        return shouldTranslate(client, operatingSystemFromPlatform(hostPlatform));
    }

    // Moonlight's keyboard protocol uses Windows virtual-key codes on every
    // client platform. Sunshine maps VK_LWIN/VK_RWIN to Command on macOS.
    // Swapping those keys with Control therefore translates the primary
    // shortcut modifier in either direction between macOS and Windows.
    static void translate(short& keyCode, char& modifiers)
    {
        switch (keyCode) {
        // MODIFIER_EXTENDED selects the E0-prefixed scancode on the host, so it
        // must follow the translated key: left Control is the only non-extended
        // key among the four.
        case 0x5B: // VK_LWIN / left Command on a macOS host
            keyCode = 0xA2; // VK_LCONTROL
            modifiers &= ~MODIFIER_EXTENDED;
            break;
        case 0x5C: // VK_RWIN / right Command on a macOS host
            keyCode = 0xA3; // VK_RCONTROL
            break;
        case 0xA2: // VK_LCONTROL
            keyCode = 0x5B; // VK_LWIN / left Command on a macOS host
            modifiers |= MODIFIER_EXTENDED;
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
