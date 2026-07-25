#include <QtTest>

#include "streaming/adaptivequalitycontroller.h"
#include "streaming/streammonitormodel.h"

class AdaptiveQualityControllerTest : public QObject
{
    Q_OBJECT

private slots:
    void lowersBitrateBeforeResolution();
    void lowersResolutionAtMinimumRecommendedBitrate();
    void bottomsOutAtFiveHundredKbps();
    void requiresStableSamplesBeforeRecovery();
    void poorSampleResetsRecoveryWindow();
    void restoresResolutionAndMaximumBitrate();
    void manualControlsApplyImmediately();
    void exposesRecoveryCountdown();
    void calculatesMonitorTelemetry();
    void ignoresUnusedFecPacketsInMonitorLoss();
    void reportsDetailedPerformanceTelemetry();
    void capsMonitorHistory();
    void parsesDisplayList();
    void rejectsMalformedDisplayList();
    void reportsManualControlLimits();
};

static std::vector<AdaptiveQualityController::Tier> qualityTiers()
{
    return {
        {1920, 1080, 6000, 10000},
        {1280, 720, 3000, 5000},
    };
}

void AdaptiveQualityControllerTest::lowersBitrateBeforeResolution()
{
    AdaptiveQualityController controller(qualityTiers(), 10000);

    auto quality = controller.update(AdaptiveQualityController::ConnectionStatus::Poor);
    QVERIFY(quality);
    QCOMPARE(quality->width, 1920);
    QCOMPARE(quality->bitrateKbps, 8000);

    quality = controller.update(AdaptiveQualityController::ConnectionStatus::Poor);
    QVERIFY(quality);
    QCOMPARE(quality->width, 1920);
    QCOMPARE(quality->bitrateKbps, 6400);

    quality = controller.update(AdaptiveQualityController::ConnectionStatus::Poor);
    QVERIFY(quality);
    QCOMPARE(quality->width, 1920);
    QCOMPARE(quality->bitrateKbps, 6000);

    quality = controller.update(AdaptiveQualityController::ConnectionStatus::Poor);
    QVERIFY(quality);
    QCOMPARE(quality->width, 1280);
    QCOMPARE(quality->height, 720);
}

void AdaptiveQualityControllerTest::lowersResolutionAtMinimumRecommendedBitrate()
{
    AdaptiveQualityController controller(qualityTiers(), 6000);

    auto quality = controller.update(AdaptiveQualityController::ConnectionStatus::Poor);

    QVERIFY(quality);
    QCOMPARE(quality->width, 1280);
    QCOMPARE(quality->height, 720);
    QCOMPARE(quality->bitrateKbps, 5000);
}

void AdaptiveQualityControllerTest::bottomsOutAtFiveHundredKbps()
{
    AdaptiveQualityController controller({{640, 360, 1000, 1000}}, 1000);

    for (int i = 0; i < 10; i++) {
        controller.update(AdaptiveQualityController::ConnectionStatus::Poor);
    }

    QCOMPARE(controller.current().bitrateKbps, 500);
    QVERIFY(!controller.update(AdaptiveQualityController::ConnectionStatus::Poor));
}

void AdaptiveQualityControllerTest::requiresStableSamplesBeforeRecovery()
{
    AdaptiveQualityController controller(qualityTiers(), 6000);
    controller.update(AdaptiveQualityController::ConnectionStatus::Poor);

    QVERIFY(!controller.update(AdaptiveQualityController::ConnectionStatus::Okay));
    QVERIFY(!controller.update(AdaptiveQualityController::ConnectionStatus::Okay));
    auto quality = controller.update(AdaptiveQualityController::ConnectionStatus::Okay);

    QVERIFY(quality);
    QCOMPARE(quality->width, 1920);
    QCOMPARE(quality->height, 1080);
}

void AdaptiveQualityControllerTest::poorSampleResetsRecoveryWindow()
{
    AdaptiveQualityController controller(qualityTiers(), 10000);
    controller.update(AdaptiveQualityController::ConnectionStatus::Poor);
    controller.update(AdaptiveQualityController::ConnectionStatus::Okay);
    controller.update(AdaptiveQualityController::ConnectionStatus::Okay);

    auto reduction = controller.update(AdaptiveQualityController::ConnectionStatus::Poor);
    QVERIFY(reduction);
    QVERIFY(!controller.update(AdaptiveQualityController::ConnectionStatus::Okay));
    QVERIFY(!controller.update(AdaptiveQualityController::ConnectionStatus::Okay));
    QVERIFY(controller.update(AdaptiveQualityController::ConnectionStatus::Okay));
}

void AdaptiveQualityControllerTest::restoresResolutionAndMaximumBitrate()
{
    AdaptiveQualityController controller(qualityTiers(), 6000);
    controller.update(AdaptiveQualityController::ConnectionStatus::Poor);

    for (int i = 0; i < 60; i++) {
        controller.update(AdaptiveQualityController::ConnectionStatus::Okay);
    }

    const auto quality = controller.current();
    QCOMPARE(quality.width, 1920);
    QCOMPARE(quality.height, 1080);
    QCOMPARE(quality.bitrateKbps, 10000);
}

void AdaptiveQualityControllerTest::manualControlsApplyImmediately()
{
    AdaptiveQualityController controller(qualityTiers(), 10000);

    auto down = controller.decreaseQuality();
    QVERIFY(down);
    QCOMPARE(down->bitrateKbps, 8000);

    auto up = controller.increaseQuality();
    QVERIFY(up);
    QCOMPARE(up->bitrateKbps, 8500);
}

void AdaptiveQualityControllerTest::exposesRecoveryCountdown()
{
    AdaptiveQualityController controller(qualityTiers(), 10000);

    QCOMPARE(controller.recoverySamplesRemaining(), 3);
    controller.update(AdaptiveQualityController::ConnectionStatus::Okay);
    QCOMPARE(controller.recoverySamplesRemaining(), 2);
    controller.update(AdaptiveQualityController::ConnectionStatus::Poor);
    QCOMPARE(controller.recoverySamplesRemaining(), 3);
}

void AdaptiveQualityControllerTest::calculatesMonitorTelemetry()
{
    StreamMonitorModel model;
    model.setQuality(1920, 1080, 10000, 9);
    model.recordCounters({1000, 80, 0}, 1000);
    model.recordCounters({1001000, 160, 8}, 2000);

    const auto& snapshot = model.snapshot();
    QCOMPARE(snapshot.throughputMbps, 8.0);
    QCOMPARE(snapshot.packetLossPercent, 10.0);
    QCOMPARE(snapshot.fecRecoveredPackets, std::uint64_t(8));
    QCOMPARE(snapshot.targetBitrateKbps, 10000);
    QCOMPARE(snapshot.secondsUntilAutoScale, 9);
    QCOMPARE(snapshot.history.size(), std::size_t(1));
}

void AdaptiveQualityControllerTest::reportsDetailedPerformanceTelemetry()
{
    StreamMonitorModel model;
    model.setNetworkLatency(10, 2);
    model.recordPerformance({1000000, 60, 59, 58, 62, 2, 1, 60, 240,
                             118000, 174000, 58000});

    const auto& snapshot = model.snapshot();
    QCOMPARE(snapshot.receivedFps, 60.0);
    QCOMPARE(snapshot.decodedFps, 59.0);
    QCOMPARE(snapshot.renderedFps, 58.0);
    QCOMPARE(snapshot.networkDroppedFramePercent, 2.0 * 100.0 / 62.0);
    QCOMPARE(snapshot.pacerDroppedFramePercent, 1.0 * 100.0 / 62.0);
    QCOMPARE(snapshot.rttMs, 10.0);
    QCOMPARE(snapshot.networkJitterMs, 2.0);
    QCOMPARE(snapshot.hostLatencyMs, 4.0);
    QCOMPARE(snapshot.decodeLatencyMs, 2.0);
    QCOMPARE(snapshot.pacerLatencyMs, 3.0);
    QCOMPARE(snapshot.renderLatencyMs, 1.0);
    QCOMPARE(snapshot.estimatedLatencyMs, 15.0);
}

void AdaptiveQualityControllerTest::ignoresUnusedFecPacketsInMonitorLoss()
{
    StreamMonitorModel model;
    model.recordCounters({1000, 100, 0}, 1000);
    model.recordCounters({1001000, 200, 0}, 2000);

    QCOMPARE(model.snapshot().packetLossPercent, 0.0);
}

void AdaptiveQualityControllerTest::capsMonitorHistory()
{
    StreamMonitorModel model(2);
    model.recordCounters({0, 0, 0}, 1000);
    model.recordCounters({100, 1, 0}, 2000);
    model.recordCounters({200, 2, 0}, 3000);
    model.recordCounters({300, 3, 0}, 4000);

    QCOMPARE(model.snapshot().history.size(), std::size_t(2));
}

void AdaptiveQualityControllerTest::parsesDisplayList()
{
    const char payload[] = {1, 0, 2, 0, 3, 0, 'O', 'n', 'e', 3, 0, 'T', 'w', 'o'};
    StreamMonitorModel model;

    QVERIFY(model.setDisplaysFromPayload(payload, sizeof(payload)));
    QCOMPARE(model.snapshot().displays.size(), std::size_t(2));
    QCOMPARE(model.snapshot().displays.at(1), std::string("Two"));
    QCOMPARE(model.snapshot().currentDisplay, 1);
}

void AdaptiveQualityControllerTest::rejectsMalformedDisplayList()
{
    const char truncated[] = {0, 0, 1, 0, 4, 0, 'B', 'a', 'd'};
    StreamMonitorModel model;

    QVERIFY(!model.setDisplaysFromPayload(truncated, sizeof(truncated)));
    QVERIFY(model.snapshot().displays.empty());
}

void AdaptiveQualityControllerTest::reportsManualControlLimits()
{
    AdaptiveQualityController controller(qualityTiers(), 10000);
    QVERIFY(!controller.canIncrease());
    QVERIFY(controller.canDecrease());

    for (int i = 0; i < 20; i++) {
        controller.decreaseQuality();
    }
    QVERIFY(controller.canIncrease());
    QVERIFY(!controller.canDecrease());
}

QTEST_APPLESS_MAIN(AdaptiveQualityControllerTest)

#include "tst_adaptivequality.moc"
