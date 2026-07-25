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
        std::uint64_t videoPackets;
        std::uint64_t recoveredVideoPackets;
    };

    struct Sample {
        double throughputMbps;
        double packetLossPercent;
        double targetBitrateMbps;
    };

    struct PerformanceCounters {
        std::uint64_t measurementDurationUs;
        std::uint64_t receivedFrames;
        std::uint64_t decodedFrames;
        std::uint64_t renderedFrames;
        std::uint64_t totalFrames;
        std::uint64_t networkDroppedFrames;
        std::uint64_t pacerDroppedFrames;
        std::uint64_t framesWithHostProcessingLatency;
        std::uint64_t totalHostProcessingLatencyMs;
        std::uint64_t totalDecodeTimeUs;
        std::uint64_t totalPacerTimeUs;
        std::uint64_t totalRenderTimeUs;
    };

    struct Snapshot {
        double throughputMbps = 0;
        double packetLossPercent = 0;
        std::uint64_t fecRecoveredPackets = 0;
        double networkDroppedFramePercent = 0;
        double pacerDroppedFramePercent = 0;
        double receivedFps = 0;
        double decodedFps = 0;
        double renderedFps = 0;
        double rttMs = 0;
        double networkJitterMs = 0;
        double hostLatencyMs = 0;
        double decodeLatencyMs = 0;
        double pacerLatencyMs = 0;
        double renderLatencyMs = 0;
        double estimatedLatencyMs = 0;
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
    void recordPerformance(const PerformanceCounters& counters);
    void setNetworkLatency(std::uint32_t rttMs, std::uint32_t jitterMs);
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

    void updateEstimatedLatency();
};
