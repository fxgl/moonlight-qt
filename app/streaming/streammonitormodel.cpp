#include "streammonitormodel.h"

#include <algorithm>
#include <utility>

StreamMonitorModel::StreamMonitorModel(std::size_t historyLimit)
    : m_HistoryLimit(std::max<std::size_t>(1, historyLimit))
{
}

void StreamMonitorModel::recordCounters(Counters counters, std::uint64_t timestampMs)
{
    if (m_HasPreviousCounters && timestampMs > m_PreviousTimestampMs &&
            counters.receivedBytes >= m_PreviousCounters.receivedBytes &&
            counters.receivedPackets >= m_PreviousCounters.receivedPackets &&
            counters.expectedVideoPackets >= m_PreviousCounters.expectedVideoPackets &&
            counters.expectedFecPackets >= m_PreviousCounters.expectedFecPackets) {
        const auto elapsedMs = timestampMs - m_PreviousTimestampMs;
        const auto receivedBytes = counters.receivedBytes - m_PreviousCounters.receivedBytes;
        const auto receivedPackets = counters.receivedPackets - m_PreviousCounters.receivedPackets;
        const auto expectedPackets =
                counters.expectedVideoPackets - m_PreviousCounters.expectedVideoPackets +
                counters.expectedFecPackets - m_PreviousCounters.expectedFecPackets;

        m_Snapshot.throughputMbps = static_cast<double>(receivedBytes) * 8.0 / elapsedMs / 1000.0;
        if (expectedPackets > 0) {
            const auto lostPackets = expectedPackets > receivedPackets ? expectedPackets - receivedPackets : 0;
            m_Snapshot.packetLossPercent = std::min(100.0,
                    static_cast<double>(lostPackets) * 100.0 / expectedPackets);
        }
        else {
            m_Snapshot.packetLossPercent = 0;
        }

        m_Snapshot.history.push_back({m_Snapshot.throughputMbps,
                                      m_Snapshot.packetLossPercent,
                                      m_Snapshot.targetBitrateKbps / 1000.0});
        if (m_Snapshot.history.size() > m_HistoryLimit) {
            m_Snapshot.history.erase(m_Snapshot.history.begin(),
                                     m_Snapshot.history.begin() +
                                     (m_Snapshot.history.size() - m_HistoryLimit));
        }
    }

    m_PreviousCounters = counters;
    m_PreviousTimestampMs = timestampMs;
    m_HasPreviousCounters = true;
}

void StreamMonitorModel::setQuality(int width, int height, int bitrateKbps, int secondsUntilAutoScale,
                                    bool adaptiveQualityEnabled,
                                    bool canIncreaseQuality,
                                    bool canDecreaseQuality)
{
    m_Snapshot.width = width;
    m_Snapshot.height = height;
    m_Snapshot.targetBitrateKbps = bitrateKbps;
    m_Snapshot.secondsUntilAutoScale = std::max(0, secondsUntilAutoScale);
    m_Snapshot.adaptiveQualityEnabled = adaptiveQualityEnabled;
    m_Snapshot.canIncreaseQuality = canIncreaseQuality;
    m_Snapshot.canDecreaseQuality = canDecreaseQuality;
}

void StreamMonitorModel::setDisplays(std::vector<std::string> displays, int currentDisplay)
{
    m_Snapshot.displays = std::move(displays);
    m_Snapshot.currentDisplay = currentDisplay >= 0 &&
            currentDisplay < static_cast<int>(m_Snapshot.displays.size()) ? currentDisplay : -1;
}

bool StreamMonitorModel::setDisplaysFromPayload(const char* payload, std::size_t length)
{
    if (!payload || length < 4) {
        return false;
    }

    const auto read16 = [](const unsigned char* bytes) {
        return static_cast<std::uint16_t>(bytes[0] | (static_cast<std::uint16_t>(bytes[1]) << 8));
    };
    const auto* cursor = reinterpret_cast<const unsigned char*>(payload);
    const auto* end = cursor + length;
    const auto current = read16(cursor);
    const auto count = read16(cursor + 2);
    cursor += 4;

    std::vector<std::string> displays;
    displays.reserve(count);
    for (std::uint16_t i = 0; i < count; i++) {
        if (end - cursor < 2) {
            return false;
        }
        const auto nameLength = read16(cursor);
        cursor += 2;
        if (end - cursor < nameLength) {
            return false;
        }
        displays.emplace_back(reinterpret_cast<const char*>(cursor), nameLength);
        cursor += nameLength;
    }
    if (cursor != end) {
        return false;
    }

    setDisplays(std::move(displays), current == UINT16_MAX ? -1 : current);
    return true;
}

const StreamMonitorModel::Snapshot& StreamMonitorModel::snapshot() const
{
    return m_Snapshot;
}
