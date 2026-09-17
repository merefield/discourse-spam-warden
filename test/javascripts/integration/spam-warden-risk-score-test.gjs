import { render } from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import { i18n } from "discourse-i18n";
import SpamWardenRiskScore from "discourse/plugins/discourse-spam-warden/discourse/components/spam-warden-risk-score";

module("Integration | Component | SpamWardenRiskScore", function (hooks) {
  setupRenderingTest(hooks);

  test("zero is a scored result and remains distinct from unavailable", async function (assert) {
    await render(
      <template>
        <SpamWardenRiskScore
          @score={{0}}
          @scored={{true}}
          @status="checked"
          @decision="allow"
        />
      </template>
    );
    assert
      .dom(".spam-warden-risk-score__value")
      .hasText("0%", "zero is displayed rather than treated as absent");
    assert
      .dom(".spam-warden-risk-score")
      .hasClass("--clear", "a clear assessment uses the success colour");
    assert
      .dom(".spam-warden-risk-score__note")
      .hasText(
        i18n("spam_warden.dashboard.score_note"),
        "the score is distinguished from a probability"
      );
  });

  test("an unavailable check cannot display a misleading zero", async function (assert) {
    await render(
      <template>
        <SpamWardenRiskScore
          @score={{0}}
          @scored={{true}}
          @status="unknown"
          @decision="unknown"
          @compact={{true}}
        />
      </template>
    );
    assert
      .dom(".spam-warden-risk-score__value")
      .doesNotExist("an outage has no numerical score");
    assert
      .dom(".spam-warden-risk-score__unscored")
      .hasText(
        i18n("spam_warden.dashboard.na"),
        "the absence of a score is explicit"
      );
    assert
      .dom(".spam-warden-risk-score")
      .hasClass("--unknown", "the outage colour is neutral");
  });

  test("zero uses green independently of the action recommendation", async function (assert) {
    await render(
      <template>
        <SpamWardenRiskScore
          @score={{0}}
          @scored={{true}}
          @status="checked"
          @decision="watch"
        />
      </template>
    );
    assert
      .dom(".spam-warden-risk-score__value")
      .hasText("0%", "the actual adjusted score is preserved");
    assert
      .dom(".spam-warden-risk-score")
      .hasClass("--clear", "zero has the green score band");
    assert
      .dom(".spam-warden-status")
      .hasText(
        i18n("spam_warden.dashboard.no_scored_concern"),
        "the label describes the score rather than an action"
      );
  });
  test("both summary sizes use red from 70 while exemptions and missing scores take precedence", async function (assert) {
    for (const compact of [false, true]) {
      for (const [score, exempt, status, modifier] of [
        [0, false, "checked", "--clear"],
        [1, false, "checked", "--caution"],
        [30, false, "checked", "--caution"],
        [31, false, "checked", "--moderate"],
        [69, false, "checked", "--moderate"],
        [70, false, "checked", "--strong"],
        [100, false, "checked", "--strong"],
        [100, true, "checked", "--exempt"],
        [100, false, "unknown", "--unknown"],
      ]) {
        await render(
          <template>
            <SpamWardenRiskScore
              @score={{score}}
              @scored={{true}}
              @status={{status}}
              @decision="review"
              @compact={{compact}}
              @exempt={{exempt}}
            />
          </template>
        );
        assert
          .dom(".spam-warden-risk-score")
          .hasClass(
            modifier,
            `${score}, ${status}, exempt ${exempt}, compact ${compact}`
          );
        if (modifier === "--strong") {
          assert
            .dom(".spam-warden-risk-score")
            .includesText(
              i18n("spam_warden.dashboard.high_concern"),
              "high concern is explicit without relying on red"
            );
        }
      }
    }
  });
});
