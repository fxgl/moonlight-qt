#pragma once

#include "streammonitormodel.h"

#include <functional>
#include <memory>

class MacStreamMonitor
{
public:
    struct Actions {
        std::function<void()> increaseQuality;
        std::function<void()> decreaseQuality;
        std::function<void()> refreshDisplays;
        std::function<void(int)> switchDisplay;
    };

    explicit MacStreamMonitor(Actions actions);
    ~MacStreamMonitor();

    void update(const StreamMonitorModel::Snapshot& snapshot);

private:
    class Impl;
    std::unique_ptr<Impl> m_Impl;
};
