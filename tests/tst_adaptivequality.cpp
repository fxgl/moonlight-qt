#include <QtTest>

#include "streaming/adaptivequalitycontroller.h"

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

QTEST_APPLESS_MAIN(AdaptiveQualityControllerTest)

#include "tst_adaptivequality.moc"
