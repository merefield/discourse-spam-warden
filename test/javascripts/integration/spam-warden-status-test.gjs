import { click, render } from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import { i18n } from "discourse-i18n";
import SpamWardenDashboard from "discourse/plugins/discourse-spam-warden/discourse/components/spam-warden-dashboard";
import SpamWardenEvidence from "discourse/plugins/discourse-spam-warden/discourse/components/spam-warden-evidence";
import SpamWardenStatus from "discourse/plugins/discourse-spam-warden/discourse/components/spam-warden-status";

module("Integration | Component | SpamWardenStatus", function (hooks) {
  setupRenderingTest(hooks);

  test("local signals explain capped contributions without replacing external evidence", async function (assert) {
    const scan = {
      decision: "review",
      status: "checked",
      source: "activity",
      action_taken: "review",
      evidence: [],
      policy: {
        weights: { confirmed_spam: 80, local_cap: 100 },
        assessment: {
          external_decision: "allow",
          base_score: 0,
          score: 25,
          scored: true,
          engagement: { adjustment: 0, level: "new_account", available: false },
          local_signals: {
            enabled: true,
            duplicate_posts: 5,
            duplicate_points: 20,
            burst_posts: 5,
            burst_topics: 3,
            burst_points: 15,
            posting_points: 25,
            confirmed_spam_posts: 0,
            history_points: 0,
            adjustment: 25,
          },
        },
      },
    };
    await render(<template><SpamWardenEvidence @scan={{scan}} /></template>);
    assert.dom(".spam-warden-evidence").includesText(
      i18n("spam_warden.dashboard.configured_weights", {
        spam_points: 80,
        cap: 100,
      }),
      "the explanation uses the saved weights and cap"
    );
    assert
      .dom(".spam-warden-evidence")
      .includesText(
        i18n("spam_warden.dashboard.local_signals"),
        "local evidence has its own section"
      );
    assert.dom(".spam-warden-evidence").includesText(
      i18n("spam_warden.dashboard.local_points", {
        duplicate: 20,
        burst: 15,
        posting: 25,
        history: 0,
        total: 25,
      }),
      "correlated contributions show the cap"
    );
    assert
      .dom(".spam-warden-evidence")
      .includesText(
        i18n("spam_warden.dashboard.local_help"),
        "thresholds and moderation safeguards are explained"
      );
    assert
      .dom(".spam-warden-risk-score__value")
      .hasText("25%", "the saved combined score is displayed");
    assert
      .dom(".spam-warden-evidence__provider .spam-warden-status")
      .hasText(
        i18n("spam_warden.decisions.allow"),
        "the clean external lookup is preserved separately"
      );
  });

  test("engagement explains the adjustment while preserving strong external evidence", async function (assert) {
    const scan = {
      decision: "review",
      status: "checked",
      action_taken: "review",
      evidence: [],
      policy: {
        assessment: {
          external_decision: "silence",
          scored: true,
          base_score: 80,
          score: 65,
          engagement: {
            available: true,
            level: "meaningful",
            adjustment: -15,
            topics_viewed: 3,
            posts_read: 10,
            reading_minutes: 3,
            reading_seconds: 180,
            days_visited: 1,
          },
        },
      },
    };
    await render(<template><SpamWardenEvidence @scan={{scan}} /></template>);
    assert
      .dom(".spam-warden-risk-score .spam-warden-status")
      .hasText(
        i18n("spam_warden.dashboard.moderate_concern"),
        "the adjusted score is in the middle band"
      );
    assert
      .dom(".spam-warden-evidence__provider .spam-warden-status")
      .hasText(
        i18n("spam_warden.decisions.silence"),
        "strong external evidence remains visible"
      );
    assert
      .dom(
        ".spam-warden-evidence__engagement .spam-warden-evidence__metrics > div"
      )
      .exists({ count: 4 }, "reading metrics are separated into four tiles");
    assert
      .dom(".spam-warden-risk-score__value")
      .hasText("65%", "the rule score is the dashboard focal point");
    assert
      .dom(".spam-warden-risk-score")
      .hasClass("--moderate", "the box reflects the middle score band");
    assert
      .dom(".spam-warden-evidence__risk")
      .includesText("-15", "the engagement adjustment is visible");
    assert
      .dom(".spam-warden-evidence__help")
      .doesNotHaveAttribute("open", "detailed guidance is collapsed initially");
    await click(".spam-warden-evidence__help summary");
    assert
      .dom(".spam-warden-evidence__help")
      .hasAttribute("open", "", "the explanation can be expanded");
  });

  test("an outage remains unscored despite positive engagement", async function (assert) {
    const scan = {
      decision: "unknown",
      status: "unknown",
      action_taken: "none",
      evidence: [],
      policy: {
        assessment: {
          external_decision: "unknown",
          scored: false,
          engagement: { level: "meaningful", adjustment: -15 },
        },
      },
    };
    await render(<template><SpamWardenEvidence @scan={{scan}} /></template>);
    assert
      .dom(".spam-warden-evidence__risk")
      .includesText(
        i18n("spam_warden.dashboard.unscored_help"),
        "the outage is not converted to a reassuring score"
      );
    assert
      .dom(".spam-warden-risk-score__value")
      .doesNotExist("an unavailable check never shows a percentage");
    assert
      .dom(".spam-warden-risk-score")
      .hasClass("--unknown", "unavailable remains neutral");
  });

  test("strong evidence has text and an icon without implying action", async function (assert) {
    await render(<template><SpamWardenStatus @decision="silence" /></template>);
    assert
      .dom(".spam-warden-status")
      .hasText(
        i18n("spam_warden.decisions.silence"),
        "evidence has an accessible text label"
      );
    assert
      .dom(".d-icon-circle-exclamation")
      .exists("shape also communicates severity");
  });

  test("unavailable checks are not presented as a clear result", async function (assert) {
    await render(<template><SpamWardenStatus @decision="unknown" /></template>);
    assert
      .dom(".spam-warden-status")
      .hasClass("--unknown", "unavailable uses a neutral state");
    assert
      .dom(".spam-warden-status")
      .hasText(
        i18n("spam_warden.decisions.unknown"),
        "unavailability is explicit"
      );
  });

  test("observation displays evidence separately from enforcement", async function (assert) {
    this.scan = {
      decision: "silence",
      action_taken: "none",
      created_at: "2026-09-05",
      evidence: [],
    };
    await render(
      <template><SpamWardenEvidence @scan={{this.scan}} /></template>
    );
    assert
      .dom(".spam-warden-status")
      .hasText(
        i18n("spam_warden.decisions.silence"),
        "strong evidence remains visible in observe mode"
      );
    assert
      .dom(".spam-warden-evidence")
      .includesText(
        i18n("spam_warden.actions.none"),
        "the UI says that no action was taken"
      );
  });

  test("skipped checks have an explicit neutral label", async function (assert) {
    await render(
      <template>
        <SpamWardenStatus @decision="unknown" @status="skipped" />
      </template>
    );
    assert
      .dom(".spam-warden-status")
      .hasClass(
        "--unknown",
        "a skipped check carries no favourable assessment"
      );
    assert
      .dom(".spam-warden-status")
      .hasText(
        i18n("spam_warden.decisions.skipped"),
        "a skipped check is distinct from a provider outage"
      );
  });

  test("dashboard explains the disabled state and retains connection testing", async function (assert) {
    this.model = { enabled: false, mode: "observe", health: {}, scans: [] };
    await render(
      <template><SpamWardenDashboard @model={{this.model}} /></template>
    );
    assert
      .dom(".spam-warden-dashboard")
      .includesText(
        i18n("spam_warden.disabled"),
        "disabled automatic checks are explicit"
      );
    assert
      .dom(".spam-warden-dashboard")
      .includesText(
        i18n("spam_warden.test"),
        "the connection check remains available"
      );
  });
});
