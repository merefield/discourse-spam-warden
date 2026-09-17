import { click, render } from "@ember/test-helpers";
import { module, test } from "qunit";
import ModalContainer from "discourse/components/modal-container";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import pretender, { response } from "discourse/tests/helpers/create-pretender";
import { i18n } from "discourse-i18n";
import SpamWardenAiEvidence from "discourse/plugins/discourse-spam-warden/discourse/components/spam-warden-ai-evidence";
import SpamWardenUser from "discourse/plugins/discourse-spam-warden/discourse/components/spam-warden-user";
import SpamWardenAiReview from "discourse/plugins/discourse-spam-warden/discourse/connectors/after-reviewable-post-body/spam-warden-ai";

module("Integration | Component | SpamWardenAiEvidence", function (hooks) {
  setupRenderingTest(hooks);

  test("AI review links request the expanded account dashboard", async function (assert) {
    this.currentUser.set("admin", true);
    const outletArgs = { model: { spam_warden_ai_account_id: 42 } };
    await render(
      <template><SpamWardenAiReview @outletArgs={{outletArgs}} /></template>
    );
    assert
      .dom(".spam-warden-ai-review a")
      .hasAttribute("href", "/admin/users/42?spamWarden=true#spam-warden");
  });

  test("staff rejection is distinct from AI classification and explanations are escaped", async function (assert) {
    this.currentUser.set("admin", true);
    const evidence = {
      entries: [
        {
          post_id: 1,
          post_url: "/t/1/1",
          reviewable_id: 2,
          is_spam: true,
          outcome: "rejected",
          reason: "<img src=x onerror=alert(1)>",
          checked_at: "2026-09-07T10:00:00Z",
        },
      ],
    };
    await render(
      <template><SpamWardenAiEvidence @evidence={{evidence}} /></template>
    );
    assert
      .dom(".spam-warden-ai-evidence h4")
      .hasText(
        i18n("spam_warden.ai.outcome.rejected"),
        "human decision is prominent"
      );
    assert
      .dom(".spam-warden-ai-evidence")
      .includesText(
        i18n("spam_warden.ai.spam"),
        "the automated finding is separately labelled"
      );
    assert
      .dom(".spam-warden-ai-evidence__reason")
      .hasText(evidence.entries[0].reason, "explanation is plain text");
    assert
      .dom(".spam-warden-ai-evidence img")
      .doesNotExist("explanation cannot inject HTML");
    assert
      .dom(".spam-warden-ai-evidence__actions button")
      .doesNotExist("rejected flags do not offer reporting");
    assert
      .dom('.spam-warden-ai-evidence a[href="/review/2"]')
      .exists("staff can open the original review");
  });

  test("confirmed findings on staff accounts retain evidence without a report action", async function (assert) {
    this.currentUser.set("admin", true);
    const user = { id: 42, admin: false, moderator: true };
    pretender.get("/admin/plugins/discourse-spam-warden/accounts/42.json", () =>
      response({
        enabled: false,
        allowed: false,
        scan: null,
        ai_evidence: {
          entries: [
            {
              post_id: 1,
              post_url: "/t/1/1",
              is_spam: true,
              outcome: "confirmed",
              checked_at: "2026-09-07T10:00:00Z",
            },
          ],
        },
      })
    );
    await render(<template><SpamWardenUser @user={{user}} /></template>);
    await click(".spam-warden-user__toggle");
    assert
      .dom(".spam-warden-ai-evidence h4")
      .hasText(
        i18n("spam_warden.ai.outcome.confirmed"),
        "retained evidence stays visible"
      );
    assert
      .dom(".spam-warden-ai-evidence__actions button")
      .doesNotExist("staff targets cannot open a report");
    assert
      .dom(".spam-warden-submission")
      .doesNotExist("the action matches submission UI availability");
  });

  test("AI evidence is hidden from moderators", async function (assert) {
    this.currentUser.setProperties({ admin: false, moderator: true });
    const evidence = { entries: [] };
    await render(
      <template><SpamWardenAiEvidence @evidence={{evidence}} /></template>
    );
    assert
      .dom(".spam-warden-ai-evidence")
      .doesNotExist("admin-only evidence stays hidden");
  });

  test("refresh reads saved evidence and confirmed findings open the existing approval dialog", async function (assert) {
    this.currentUser.set("admin", true);
    const user = { id: 42, admin: false, moderator: false };
    let loads = 0;
    let previews = 0;
    pretender.get(
      "/admin/plugins/discourse-spam-warden/accounts/42.json",
      () => {
        loads++;
        return response({
          enabled: false,
          allowed: false,
          scan: null,
          submission_configured: true,
          ai_evidence: {
            entries: [
              {
                post_id: 1,
                post_url: "/t/1/1",
                is_spam: true,
                outcome: "confirmed",
                checked_at: "2026-09-07T10:00:00Z",
              },
            ],
          },
        });
      }
    );
    pretender.get(
      "/admin/plugins/discourse-spam-warden/accounts/42/submission.json",
      () => {
        previews++;
        return response({
          configured: true,
          preview: {
            destination: "https://www.stopforumspam.com/add",
            username: "spammer",
            email: "spam@example.com",
            ip_address: "8.8.4.4",
            evidence: "https://forum.example/t/1/1\nConfirmed spam",
            token: "signed-preview",
          },
        });
      }
    );
    await render(
      <template><ModalContainer /><SpamWardenUser @user={{user}} /></template>
    );
    await click(".spam-warden-user__toggle");
    await click(".spam-warden-ai-evidence > button");
    assert.strictEqual(
      loads,
      2,
      "refresh fetches saved evidence without a new reputation or AI check"
    );
    await click(".spam-warden-ai-evidence__actions button");
    assert.strictEqual(previews, 1, "the account preview is fetched");
    assert
      .dom(".spam-warden-submission-confirmation")
      .includesText(
        "spam@example.com",
        "the exact identifiers are shown before approval"
      );
    await click(".spam-warden-submission-confirmation__cancel");
    assert
      .dom(".spam-warden-submission-confirmation")
      .doesNotExist("cancel closes the dialog without submitting");
  });
});
