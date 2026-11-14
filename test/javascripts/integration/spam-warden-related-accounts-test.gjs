import { click, render } from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import pretender from "discourse/tests/helpers/create-pretender";
import SpamWardenRelatedAccounts from "discourse/plugins/discourse-spam-warden/discourse/components/spam-warden-related-accounts";

module("Integration | Component | SpamWardenRelatedAccounts", function (hooks) {
  setupRenderingTest(hooks);

  test("loads another page and refreshes live connections without retaining removed rows", async function (assert) {
    let refreshed = false;
    pretender.get(
      "/admin/plugins/discourse-spam-warden/accounts/12/related.json",
      (request) => {
        const second = request.queryParams.after_id === "13";
        return [
          200,
          { "Content-Type": "application/json" },
          JSON.stringify({
            total: refreshed ? 0 : 2,
            days: 30,
            threshold: 30,
            enabled: false,
            eligible: true,
            next_after_id: second || refreshed ? null : 13,
            accounts: refreshed
              ? []
              : [
                  {
                    id: second ? 14 : 13,
                    username: second ? "second" : "first",
                    independent_score: 0,
                    qualifies: false,
                    connections: [],
                    connection_types: [],
                  },
                ],
          }),
        ];
      }
    );
    await render(
      <template><SpamWardenRelatedAccounts @userId={{12}} /></template>
    );
    assert.dom("tbody tr").exists({ count: 1 }, "starts with one page");
    await click(".spam-warden-related > .btn-default");
    assert.dom("tbody tr").exists({ count: 2 }, "appends the next page");
    refreshed = true;
    await click(".spam-warden-related .btn-flat");
    assert.dom("tbody tr").doesNotExist("refresh removes old relationships");
    assert
      .dom(".spam-warden-related")
      .includesText("No matching accounts", "explains the empty state");
    assert
      .dom(".spam-warden-related")
      .includesText("context only", "disabled scoring is explicit");
  });

  test("shows connection types, separate saved points, evidence dates and account links", async function (assert) {
    pretender.get(
      "/admin/plugins/discourse-spam-warden/accounts/12/related.json",
      () => [
        200,
        { "Content-Type": "application/json" },
        JSON.stringify({
          total: 1,
          days: 30,
          threshold: 30,
          enabled: true,
          eligible: true,
          own_qualifies: true,
          own_score: 40,
          saved_points: 15,
          saved_at: "2026-10-01T12:00:00Z",
          accounts: [
            {
              id: 13,
              username: "related",
              independent_score: null,
              qualifies: false,
              connection_types: [
                { source: "registration", peer_source: "latest_access" },
              ],
              connections: [
                {
                  ip: "203.0.113.8",
                  source: "registration",
                  peer_source: "latest_access",
                  at: "2026-10-01T12:00:00Z",
                  peer_at: "2026-10-02T12:00:00Z",
                },
              ],
            },
          ],
        }),
      ]
    );
    await render(
      <template><SpamWardenRelatedAccounts @userId={{12}} /></template>
    );
    assert
      .dom(".spam-warden-related")
      .includesText(
        "Saved shared-IP factor: 15",
        "distinguishes the saved contribution"
      );
    assert
      .dom(".spam-warden-related")
      .includesText(
        "This account independently scores 40",
        "includes the suspicious account itself"
      );
    assert
      .dom(".d-table")
      .includesText(
        "Registration ↔ Latest access address",
        "shows the connection type before expansion"
      );
    assert
      .dom(".d-table")
      .includesText("N/A", "does not turn unknown evidence into a zero score");
    assert
      .dom("a")
      .hasAttribute(
        "href",
        "/admin/users/13/related?spamWarden=true#spam-warden",
        "opens the related dashboard"
      );
    await click("details summary");
    assert
      .dom("details")
      .includesText("203.0.113.8", "shows the matched IP in details");
    assert
      .dom(".spam-warden-related")
      .includesText(
        "not a verified observation",
        "qualifies the date accuracy"
      );
  });
});
