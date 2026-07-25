QT += core testlib
CONFIG += c++17 console testcase
CONFIG -= app_bundle
TEMPLATE = app
TARGET = tst_adaptivequality

INCLUDEPATH += ../app

SOURCES += \
    tst_adaptivequality.cpp \
    ../app/streaming/adaptivequalitycontroller.cpp \
    ../app/streaming/streammonitormodel.cpp

HEADERS += \
    ../app/streaming/adaptivequalitycontroller.h \
    ../app/streaming/streammonitormodel.h
