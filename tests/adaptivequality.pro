QT += core testlib
CONFIG += c++17 console testcase
CONFIG -= app_bundle
TEMPLATE = app
TARGET = tst_adaptivequality

INCLUDEPATH += ../app ../moonlight-common-c/moonlight-common-c/src

SOURCES += \
    tst_adaptivequality.cpp \
    ../app/streaming/adaptivequalitycontroller.cpp \
    ../app/streaming/streammonitormodel.cpp \
    ../app/streaming/input/keyboardlayout.cpp

HEADERS += \
    ../app/streaming/adaptivequalitycontroller.h \
    ../app/streaming/streammonitormodel.h \
    ../app/streaming/input/keyboardlayout.h

macx {
    OBJECTIVE_SOURCES += ../app/streaming/input/keyboardlayout_mac.mm
    LIBS += -framework Carbon
}

win32 {
    SOURCES += ../app/streaming/input/keyboardlayout_win.cpp
    LIBS += user32.lib
}
