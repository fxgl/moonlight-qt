#pragma once

#include <QByteArray>

// Native access to the general pasteboard for clipboard image sync. Qt's
// clipboard change detection relies on events Session suspends while streaming,
// and its image path decodes into QImage; this reads and writes PNG bytes directly.
namespace MacClipboard
{
// Increments whenever any application changes the general pasteboard.
long changeCount();

bool hasImage();

// PNG data for the pasteboard image (converted from TIFF if needed), or empty
// when there is no image or it would exceed maxBytes.
QByteArray imagePng(qsizetype maxBytes);

// Replaces the pasteboard contents with the image as PNG and TIFF.
bool setImagePng(const QByteArray& png);
}
