#include "keyboardlayout.h"

#include <windows.h>

#include <QString>

KeyboardLayout::Descriptor KeyboardLayout::current()
{
    const HKL keyboardLayout = GetKeyboardLayout(0);
    if (!keyboardLayout) {
        return {};
    }

    wchar_t localeName[LOCALE_NAME_MAX_LENGTH] = {};
    if (LCIDToLocaleName(MAKELCID(LOWORD(reinterpret_cast<ULONG_PTR>(keyboardLayout)), SORT_DEFAULT),
                         localeName,
                         LOCALE_NAME_MAX_LENGTH,
                         0) == 0) {
        return {};
    }

    wchar_t layoutName[KL_NAMELENGTH] = {};
    if (!GetKeyboardLayoutNameW(layoutName)) {
        return {};
    }

    Descriptor descriptor;
    descriptor.platform = LI_KEYBOARD_LAYOUT_PLATFORM_WINDOWS;
    descriptor.language = QString::fromWCharArray(localeName).toUtf8();
    descriptor.layoutId = QString::fromWCharArray(layoutName).toUtf8();
    return descriptor;
}
