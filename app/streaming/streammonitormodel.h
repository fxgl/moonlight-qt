#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

class StreamMonitorModel
{
public:
    struct Counters {
        std::uint64_t receivedBytes;
        std::uint64_t receivedPackets;
        std::uint64_t expectedVideoPackets;
        std::uint64_t expectedFecPackets;
    };

    struct Sample {
        double throughputMbps;
        double packetLossPercent;
        double targetBitrateMbps;
    };

    struct Snapshot {
        double throughputMbps = 0;
        double packetLossPercent = 0;
        int targetBitrateKbps = 0;
        int width = 0;
        int height = 0;
        int secondsUntilAutoScale = 0;
        bool adaptiveQualityEnabled = false;
        bool canIncreaseQuality = false;
        bool canDecreaseQuality = false;
        std::vector<Sample> history;
        std::vector<std::string> displays;
        int currentDisplay = -1;
    };

    explicit StreamMonitorModel(std::size_t historyLimit = 60);

    void recordCounters(Counters counters, std::uint64_t timestampMs);
    void setQuality(int width, int height, int bitrateKbps, int secondsUntilAutoScale,
                    bool adaptiveQualityEnabled = true,
                    bool canIncreaseQuality = true,
                    bool canDecreaseQuality = true);
    void setDisplays(std::vector<std::string> displays, int currentDisplay);
    bool setDisplaysFromPayload(const char* payload, std::size_t length);
    const Snapshot& snapshot() const;

private:
    std::size_t m_HistoryLimit;
    Snapshot m_Snapshot;
    Counters m_PreviousCounters {};
    std::uint64_t m_PreviousTimestampMs = 0;
    bool m_HasPreviousCounters = false;
};
