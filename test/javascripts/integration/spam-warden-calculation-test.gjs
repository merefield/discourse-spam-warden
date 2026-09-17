import { render } from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import { i18n } from "discourse-i18n";
import SpamWardenEvidence from "discourse/plugins/discourse-spam-warden/discourse/components/spam-warden-evidence";

module("Integration | Component | SpamWardenCalculation", function (hooks) {
  setupRenderingTest(hooks);

  test("saved report arithmetic is separate from raw evidence and current settings", async function (assert) {
    this.siteSettings.spam_warden_email_report_points = 99;
    const scan = {
      status: "checked",
      decision: "watch",
      action_taken: "none",
      evidence: [
        { field: "email", appears: true, frequency: 3, confidence: 40 },
      ],
      policy: {
        version: 8,
        external_weights: { full_weight_days: 7, half_weight_days: 30 },
        weights: { confirmed_spam: 85 },
        assessment: {
          scored: true,
          score: 49,
          external_decision: "watch",
          engagement: { adjustment: 10, available: false, level: "none" },
          external_scoring: {
            points: { email: 24, ip: 15 },
            fields: {
              email: {
                reports: 3,
                weight: 8,
                cap: 60,
                multiplier: 1,
                reason: "full",
                points: 24,
              },
              ip: {
                reports: 5,
                weight: 3,
                cap: 30,
                multiplier: 1,
                reason: "full",
                points: 15,
              },
            },
          },
          calculation: {
            external: 39,
            posting: 0,
            additional: 0,
            capped_local: 0,
            local_cap: 100,
            reading: 10,
            suspicion: 49,
            confirmed: 0,
            total: 49,
          },
        },
      },
    };
    await render(<template><SpamWardenEvidence @scan={{scan}} /></template>);
    assert.dom(".spam-warden-evidence__summary").hasText(
      i18n("spam_warden.calculation.summary", {
        email: 24,
        ip: 15,
        adjustment: 10,
      }),
      "summary uses the saved contributions"
    );
    assert
      .dom(".spam-warden-calculation")
      .includesText(
        "3 reports × 8",
        "saved weight is used instead of today's setting"
      );
    assert
      .dom(".spam-warden-calculation__total dd")
      .hasText("49%", "the calculation total agrees with the score");
    assert
      .dom(".spam-warden-evidence__body .spam-warden-evidence__report-count")
      .hasText("3 reports.", "raw evidence remains separate");
    assert
      .dom(".spam-warden-evidence__body .spam-warden-calculation")
      .doesNotExist("calculations have their own column");
  });

  test("confirmed spam is explained after reading floors other suspicion", async function (assert) {
    const scan = {
      status: "checked",
      decision: "review",
      action_taken: "review",
      evidence: [],
      policy: {
        weights: { confirmed_spam: 85 },
        assessment: {
          scored: true,
          score: 85,
          engagement: { level: "sustained", adjustment: -15 },
          local_signals: { confirmed_spam_posts: 1 },
          calculation: {
            external: 0,
            posting: 0,
            additional: 0,
            capped_local: 0,
            local_cap: 100,
            reading: -15,
            suspicion: 0,
            confirmed: 85,
            total: 85,
          },
        },
      },
    };
    await render(<template><SpamWardenEvidence @scan={{scan}} /></template>);
    assert.dom(".spam-warden-evidence__summary").hasText(
      i18n("spam_warden.calculation.confirmed_summary", {
        suspicion: 0,
        confirmed: 85,
      }),
      "summary distinguishes suspicion from confirmed misconduct"
    );
    assert
      .dom(".spam-warden-calculation__subtotal dd")
      .hasText("0", "negative suspicion is floored before confirmation");
    assert
      .dom(".spam-warden-calculation")
      .includesText("1 post × 85", "confirmed contribution is explicit");
    assert
      .dom(".spam-warden-risk-score__value")
      .hasText("85%", "reading does not discount the confirmed post");
  });

  test("historical assessments keep their saved score without invented per-report arithmetic", async function (assert) {
    const scan = {
      status: "checked",
      decision: "review",
      action_taken: "review",
      evidence: [],
      policy: {
        version: 7,
        assessment: {
          scored: true,
          score: 70,
          base_score: 0,
          engagement: { level: "sustained", adjustment: -15 },
          local_signals: { enabled: true, adjustment: 85 },
        },
      },
    };
    await render(<template><SpamWardenEvidence @scan={{scan}} /></template>);
    assert
      .dom(".spam-warden-evidence__summary")
      .hasText(
        i18n("spam_warden.calculation.legacy_summary"),
        "the old scoring method is labelled"
      );
    assert
      .dom(".spam-warden-risk-score__value")
      .hasText("70%", "old results are not recomputed");
    assert
      .dom(".spam-warden-calculation__formula")
      .doesNotExist("no new formula is invented for the old record");
  });
});
