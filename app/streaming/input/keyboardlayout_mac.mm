#include "keyboardlayout.h"

#import <Carbon/Carbon.h>

#include <cstring>

namespace {
QByteArray cfStringToUtf8(CFStringRef value)
{
    if (!value) {
        return {};
    }

    const CFIndex length = CFStringGetLength(value);
    const CFIndex capacity = CFStringGetMaximumSizeForEncoding(length, kCFStringEncodingUTF8) + 1;
    QByteArray utf8(static_cast<qsizetype>(capacity), '\0');
    if (!CFStringGetCString(value, utf8.data(), capacity, kCFStringEncodingUTF8)) {
        return {};
    }
    utf8.truncate(static_cast<qsizetype>(strlen(utf8.constData())));
    return utf8;
}
} // namespace

KeyboardLayout::Descriptor KeyboardLayout::current()
{
    TISInputSourceRef source = TISCopyCurrentKeyboardInputSource();
    if (!source) {
        return {};
    }

    Descriptor descriptor;
    descriptor.platform = LI_KEYBOARD_LAYOUT_PLATFORM_MACOS;
    descriptor.layoutId =
        cfStringToUtf8(static_cast<CFStringRef>(TISGetInputSourceProperty(source, kTISPropertyInputSourceID)));

    const auto languages = static_cast<CFArrayRef>(TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages));
    if (languages && CFArrayGetCount(languages) != 0) {
        descriptor.language = cfStringToUtf8(static_cast<CFStringRef>(CFArrayGetValueAtIndex(languages, 0)));
    }

    CFRelease(source);
    return descriptor;
}
