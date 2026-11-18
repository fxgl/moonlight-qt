#include "macclipboard.h"

#import <AppKit/AppKit.h>

namespace MacClipboard
{

long changeCount()
{
    @autoreleasepool {
        return static_cast<long>([NSPasteboard generalPasteboard].changeCount);
    }
}

bool hasImage()
{
    @autoreleasepool {
        return [[NSPasteboard generalPasteboard] availableTypeFromArray:@[NSPasteboardTypePNG, NSPasteboardTypeTIFF]] != nil;
    }
}

QByteArray imagePng(qsizetype maxBytes)
{
    @autoreleasepool {
        NSPasteboard* pasteboard = [NSPasteboard generalPasteboard];
        NSData* png = [pasteboard dataForType:NSPasteboardTypePNG];
        if (png == nil) {
            NSData* tiff = [pasteboard dataForType:NSPasteboardTypeTIFF];
            NSBitmapImageRep* rep = tiff != nil ? [NSBitmapImageRep imageRepWithData:tiff] : nil;
            png = rep != nil ? [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] : nil;
        }
        if (png == nil || png.length == 0 || static_cast<qsizetype>(png.length) > maxBytes) {
            return {};
        }
        return QByteArray(static_cast<const char*>(png.bytes), static_cast<qsizetype>(png.length));
    }
}

bool setImagePng(const QByteArray& png)
{
    @autoreleasepool {
        NSData* data = [NSData dataWithBytes:png.constData() length:static_cast<NSUInteger>(png.size())];
        NSBitmapImageRep* rep = [NSBitmapImageRep imageRepWithData:data];
        if (rep == nil) {
            return false;
        }

        // Some apps only read TIFF, so offer both representations.
        NSData* tiff = [rep TIFFRepresentation];
        NSPasteboard* pasteboard = [NSPasteboard generalPasteboard];
        [pasteboard clearContents];
        [pasteboard declareTypes:tiff != nil ? @[NSPasteboardTypePNG, NSPasteboardTypeTIFF] : @[NSPasteboardTypePNG]
                           owner:nil];
        return [pasteboard setData:data forType:NSPasteboardTypePNG] &&
               (tiff == nil || [pasteboard setData:tiff forType:NSPasteboardTypeTIFF]);
    }
}

}
