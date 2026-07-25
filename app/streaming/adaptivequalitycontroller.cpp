#include "adaptivequalitycontroller.h"

#include <algorithm>
#include <cassert>
#include <utility>

bool AdaptiveQualityController::Quality::operator==(const Quality& other) const
{
    return width == other.width && height == other.height && bitrateKbps == other.bitrateKbps;
}

AdaptiveQualityController::AdaptiveQualityController(std::vector<Tier> tiers, int initialBitrateKbps)
    : m_Tiers(std::move(tiers)),
      m_TierIndex(0),
      m_BitrateKbps(initialBitrateKbps),
      m_RecoverySamples(0)
{
    assert(!m_Tiers.empty());
    assert(initialBitrateKbps > 0);
}

std::optional<AdaptiveQualityController::Quality>
AdaptiveQualityController::update(ConnectionStatus status)
{
    if (status == ConnectionStatus::Poor) {
        m_RecoverySamples = 0;
        return applyDecrease();
    }

    // Require three clean samples before probing upward. Reductions happen
    // immediately, while recovery is deliberately conservative to avoid oscillation.
    if (++m_RecoverySamples < RecoverySampleCount) {
        return std::nullopt;
    }
    m_RecoverySamples = 0;
    return applyIncrease();
}

std::optional<AdaptiveQualityController::Quality> AdaptiveQualityController::increaseQuality()
{
    m_RecoverySamples = 0;
    return applyIncrease();
}

std::optional<AdaptiveQualityController::Quality> AdaptiveQualityController::decreaseQuality()
{
    m_RecoverySamples = 0;
    return applyDecrease();
}

std::optional<AdaptiveQualityController::Quality> AdaptiveQualityController::applyDecrease()
{
    const auto previous = current();
    const auto& tier = m_Tiers.at(m_TierIndex);
    if (m_BitrateKbps > tier.minimumBitrateKbps) {
        m_BitrateKbps = std::max(tier.minimumBitrateKbps, m_BitrateKbps * 80 / 100);
    }
    else if (m_TierIndex + 1 < m_Tiers.size()) {
        m_TierIndex++;
        m_BitrateKbps = std::min(m_BitrateKbps, m_Tiers.at(m_TierIndex).maximumBitrateKbps);
    }
    else if (m_BitrateKbps > 500) {
        m_BitrateKbps = std::max(500, m_BitrateKbps * 80 / 100);
    }

    const auto next = current();
    return next == previous ? std::nullopt : std::optional<Quality>(next);
}

std::optional<AdaptiveQualityController::Quality> AdaptiveQualityController::applyIncrease()
{
    const auto previous = current();
    if (m_TierIndex > 0) {
        const auto& currentTier = m_Tiers.at(m_TierIndex);
        const auto& higherTier = m_Tiers.at(m_TierIndex - 1);
        const int resolutionUpgradeBitrate = std::min(higherTier.minimumBitrateKbps,
                                                      currentTier.maximumBitrateKbps);
        if (m_BitrateKbps < resolutionUpgradeBitrate) {
            m_BitrateKbps = std::min(resolutionUpgradeBitrate,
                                     m_BitrateKbps + std::max(500, resolutionUpgradeBitrate / 10));
        }
        else {
            m_TierIndex--;
            m_BitrateKbps = std::min(m_BitrateKbps, m_Tiers.at(m_TierIndex).maximumBitrateKbps);
        }
    }
    else if (m_BitrateKbps < m_Tiers.front().maximumBitrateKbps) {
        m_BitrateKbps = std::min(m_Tiers.front().maximumBitrateKbps,
                                 m_BitrateKbps + std::max(500, m_Tiers.front().maximumBitrateKbps / 20));
    }

    const auto next = current();
    return next == previous ? std::nullopt : std::optional<Quality>(next);
}

AdaptiveQualityController::Quality AdaptiveQualityController::current() const
{
    const auto& tier = m_Tiers.at(m_TierIndex);
    return {tier.width, tier.height, m_BitrateKbps};
}

int AdaptiveQualityController::recoverySamplesRemaining() const
{
    return RecoverySampleCount - m_RecoverySamples;
}

bool AdaptiveQualityController::canIncrease() const
{
    return m_TierIndex > 0 || m_BitrateKbps < m_Tiers.front().maximumBitrateKbps;
}

bool AdaptiveQualityController::canDecrease() const
{
    const auto& tier = m_Tiers.at(m_TierIndex);
    return m_BitrateKbps > tier.minimumBitrateKbps ||
            m_TierIndex + 1 < m_Tiers.size() ||
            m_BitrateKbps > 500;
}
