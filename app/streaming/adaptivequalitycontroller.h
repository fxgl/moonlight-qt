#pragma once

#include <optional>
#include <vector>

class AdaptiveQualityController
{
public:
    enum class ConnectionStatus {
        Okay,
        Poor,
    };

    struct Tier {
        int width;
        int height;
        int minimumBitrateKbps;
        int maximumBitrateKbps;
    };

    struct Quality {
        int width;
        int height;
        int bitrateKbps;

        bool operator==(const Quality& other) const;
    };

    AdaptiveQualityController(std::vector<Tier> tiers, int initialBitrateKbps);

    std::optional<Quality> update(ConnectionStatus status);
    Quality current() const;

private:
    std::vector<Tier> m_Tiers;
    std::size_t m_TierIndex;
    int m_BitrateKbps;
    int m_RecoverySamples;
};
