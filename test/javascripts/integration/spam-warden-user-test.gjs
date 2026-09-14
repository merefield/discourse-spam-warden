import { click, render } from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import pretender, { response } from "discourse/tests/helpers/create-pretender";
import { i18n } from "discourse-i18n";
import SpamWardenUser from "discourse/plugins/discourse-spam-warden/discourse/components/spam-warden-user";

module("Integration | Component | SpamWardenUser", function (hooks) {
  setupRenderingTest(hooks);

  test("an exemption updates the dashboard and removing it restores the assessment", async function (assert) {
    this.currentUser.set("admin", true);
    const user = { id: 42, admin: false, moderator: false };
    let allowed = false;
    pretender.get("/admin/plugins/discourse-spam-warden/accounts/42.json", () =>
      response({
        enabled: false,
        allowed,
        scan: {
          status: "checked",
          decision: "silence",
          action_taken: "none",
          evidence: [],
          policy: {
            assessment: {
              score: 80,
              scored: true,
              engagement: { level: "unavailable", available: false },
            },
          },
        },
      })
    );
    pretender.put(
      "/admin/plugins/discourse-spam-warden/accounts/42/exception",
      () => {
        allowed = !allowed;
        return response({ success: true });
      }
    );
    await render(<template><SpamWardenUser @user={{user}} /></template>);
    await click(".spam-warden-user__toggle");
    await click(".spam-warden-user__exception");
    assert
      .dom(".spam-warden-risk-score")
      .hasClass("--exempt", "allowing updates the box immediately");
    assert
      .dom(".spam-warden-risk-score__override")
      .hasText(
        i18n("spam_warden.dashboard.exempt"),
        "the override is labelled"
      );
    assert
      .dom(".spam-warden-risk-score__value")
      .hasText("80%", "the saved assessment is preserved");
    await click(".spam-warden-user__exception");
    assert
      .dom(".spam-warden-risk-score")
      .hasClass("--strong", "removing the override restores the risk colour");
    assert
      .dom(".spam-warden-risk-score__override")
      .doesNotExist("the exemption label is removed");
  });

  test("an exempt account without a scan still shows its override", async function (assert) {
    this.currentUser.set("admin", true);
    const user = { id: 42, admin: false, moderator: false };
    pretender.get("/admin/plugins/discourse-spam-warden/accounts/42.json", () =>
      response({ enabled: false, allowed: true, scan: null })
    );
    await render(<template><SpamWardenUser @user={{user}} /></template>);
    await click(".spam-warden-user__toggle");
    assert
      .dom(".spam-warden-risk-score")
      .hasClass("--exempt", "an exemption does not require a scan");
    assert
      .dom(".spam-warden-risk-score__value")
      .doesNotExist("no score is invented");
  });

  test("the list deep link opens the dashboard without clicking the details button", async function (assert) {
    this.currentUser.set("admin", true);
    const user = { id: 42, admin: false, moderator: false };
    pretender.get("/admin/plugins/discourse-spam-warden/accounts/42.json", () =>
      response({
        enabled: false,
        allowed: false,
        scan: {
          status: "checked",
          decision: "allow",
          action_taken: "none",
          created_at: "2026-09-05T10:00:00Z",
          evidence: [],
          policy: {
            assessment: {
              score: 0,
              scored: true,
              external_decision: "allow",
              engagement: { level: "new_account", available: false },
            },
          },
        },
      })
    );
    const originalURL = window.location.href;
    try {
      window.history.replaceState(null, "", "#spam-warden");
      await render(<template><SpamWardenUser @user={{user}} /></template>);

      assert
        .dom("#spam-warden .spam-warden-evidence")
        .exists("the dashboard has opened automatically");
      assert
        .dom("#spam-warden .spam-warden-risk-score__value")
        .hasText("0%", "an actual zero score is preserved");
    } finally {
      window.history.replaceState(null, "", originalURL);
    }
  });

  test("ordinary account navigation leaves details collapsed", async function (assert) {
    this.currentUser.set("admin", true);
    const user = { id: 42, admin: false, moderator: false };
    await render(<template><SpamWardenUser @user={{user}} /></template>);
    assert
      .dom(".spam-warden-evidence")
      .doesNotExist(
        "the deep-link behaviour does not change ordinary navigation"
      );
  });

  test("the header expands and collapses the dashboard", async function (assert) {
    this.currentUser.set("admin", true);
    const user = { id: 42, admin: false, moderator: false };
    let loads = 0;
    pretender.get(
      "/admin/plugins/discourse-spam-warden/accounts/42.json",
      () => {
        loads++;
        return response({ enabled: false, allowed: false, scan: null });
      }
    );
    await render(<template><SpamWardenUser @user={{user}} /></template>);
    assert
      .dom(".spam-warden-user__title")
      .hasText(
        i18n("spam_warden.title"),
        "the heading replaces the details button"
      );
    assert
      .dom(".spam-warden-user__toggle")
      .hasAttribute("aria-expanded", "false", "collapsed state is accessible");
    await click(".spam-warden-user__title");
    assert
      .dom(".spam-warden-evidence")
      .exists("clicking the title opens saved details");
    assert
      .dom(".spam-warden-user__toggle")
      .hasAttribute("aria-expanded", "true", "expanded state is accessible");
    await click(".spam-warden-user__toggle .d-icon");
    assert
      .dom(".spam-warden-evidence")
      .doesNotExist("clicking the chevron collapses details");
    await click(".spam-warden-user__toggle");
    assert.strictEqual(loads, 1, "expanding again retains loaded details");
    assert
      .dom(".spam-warden-user__header button")
      .exists({ count: 1 }, "the entire header is one native button");
    assert.dom(".spam-warden-evidence").exists("the dashboard can be reopened");
  });
});
