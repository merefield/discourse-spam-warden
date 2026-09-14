import { click, render } from "@ember/test-helpers";
import { module, test } from "qunit";
import ModalContainer from "discourse/components/modal-container";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import pretender, { response } from "discourse/tests/helpers/create-pretender";
import form from "discourse/tests/helpers/form-kit-helper";
import { i18n } from "discourse-i18n";
import SpamWardenSubmission from "discourse/plugins/discourse-spam-warden/discourse/components/spam-warden-submission";

module("Integration | Component | SpamWardenSubmission", function (hooks) {
  setupRenderingTest(hooks);

  hooks.beforeEach(function () {
    this.currentUser.set("admin", true);
  });

  test("audit events link named approvers and retain deleted-account IDs", async function (assert) {
    const submission = {
      status: "submitted",
      attempts: 1,
      events: [
        {
          status: "approved",
          at: "2026-09-09T12:00:00Z",
          actor_id: 3093,
          actor_username: "admin_name",
        },
        {
          status: "submitted",
          at: "2026-09-09T12:01:00Z",
          actor_id: 3094,
          actor_username: null,
        },
      ],
    };
    await render(
      <template>
        <SpamWardenSubmission
          @userId={{42}}
          @configured={{true}}
          @submission={{submission}}
        />
      </template>
    );
    await click(".spam-warden-submission details summary");
    assert
      .dom(".spam-warden-submission details a")
      .hasText("Approved by @admin_name")
      .hasAttribute("href", "/admin/users/3093/admin_name");
    assert
      .dom(".spam-warden-submission details")
      .includesText("Approved by admin ID 3094");
  });

  test("preview requires explicit approval and sends only the signed token", async function (assert) {
    let submissions = 0;
    pretender.get(
      "/admin/plugins/discourse-spam-warden/accounts/42/submission.json",
      () =>
        response({
          configured: true,
          submission: null,
          preview: {
            destination: "https://www.stopforumspam.com/add",
            username: "spammer",
            email: "spam@example.com",
            ip_address: "8.8.4.4",
            evidence:
              "https://forum.example/t/123/1\n<script>alert('spam')</script>",
            token: "signed-preview",
          },
        })
    );
    pretender.post(
      "/admin/plugins/discourse-spam-warden/accounts/42/submission",
      (request) => {
        submissions++;
        const body = new URLSearchParams(request.requestBody);
        assert.deepEqual(
          [...body.keys()].sort(),
          ["confirmed", "token"],
          "identifiers and evidence cannot be edited in the request"
        );
        assert.strictEqual(
          body.get("token"),
          "signed-preview",
          "approval refers to the preview"
        );
        assert.strictEqual(
          body.get("confirmed"),
          "true",
          "approval is explicit"
        );
        return response({
          submission: { status: "pending", attempts: 0, events: [] },
        });
      }
    );
    await render(
      <template>
        <ModalContainer />
        <SpamWardenSubmission @userId={{42}} @configured={{true}} />
      </template>
    );
    await click(".spam-warden-submission__preview");
    assert
      .dom(".spam-warden-submission-confirmation")
      .hasAttribute("role", "dialog", "approval opens a modal dialog");
    assert
      .dom(".spam-warden-submission-confirmation")
      .includesText(
        "https://www.stopforumspam.com/add",
        "destination is shown"
      );
    assert
      .dom(".spam-warden-submission-confirmation")
      .includesText("spammer", "exact username is shown");
    assert.strictEqual(submissions, 0, "preview does not submit externally");
    await click(".spam-warden-submission-confirmation__cancel");
    assert
      .dom(".spam-warden-submission-confirmation")
      .doesNotExist("cancel closes the preview");
    assert.strictEqual(submissions, 0, "cancel does not submit anything");
    await click(".spam-warden-submission__preview");
    assert
      .dom(".spam-warden-submission-confirmation")
      .includesText("spam@example.com", "exact email is visible");
    assert
      .dom(".spam-warden-submission-confirmation")
      .includesText("8.8.4.4", "exact registration IP is visible");
    assert
      .dom(".spam-warden-submission-confirmation pre")
      .includesText("<script>", "evidence is rendered as text");
    assert
      .dom(".spam-warden-submission-confirmation script")
      .doesNotExist("evidence cannot inject markup");
    await form().submit();
    assert.strictEqual(submissions, 0, "unchecked approval blocks submission");
    await form().field("confirmed").toggle();
    await form().submit();
    assert.strictEqual(submissions, 1, "approved report is queued once");
    assert
      .dom(".spam-warden-submission__status")
      .hasText(
        i18n("spam_warden.submission.status.pending"),
        "delivery status is shown"
      );
    assert
      .dom(".spam-warden-submission-confirmation form")
      .doesNotExist("approval form disappears after queueing");
  });

  test("uncertain delivery shows recovery guidance without another submission form", async function (assert) {
    const submission = { status: "unknown", attempts: 1, events: [] };
    pretender.get(
      "/admin/plugins/discourse-spam-warden/accounts/42/submission.json",
      () => response({ configured: true, submission, preview: null })
    );
    await render(
      <template>
        <ModalContainer />
        <SpamWardenSubmission
          @userId={{42}}
          @configured={{true}}
          @submission={{submission}}
        />
      </template>
    );
    await click(".spam-warden-submission__preview");
    assert
      .dom(".spam-warden-submission")
      .includesText(
        i18n("spam_warden.submission.help.unknown"),
        "uncertain delivery explains why retry is blocked"
      );
    assert
      .dom(".spam-warden-submission-confirmation form")
      .doesNotExist("no blind retry is offered");
  });

  test("refresh uses the latest reporting configuration", async function (assert) {
    let configured = false;
    pretender.get(
      "/admin/plugins/discourse-spam-warden/accounts/42/submission.json",
      () => response({ configured, submission: null, preview: null })
    );
    await render(
      <template>
        <ModalContainer /><SpamWardenSubmission
          @userId={{42}}
          @configured={{true}}
        />
      </template>
    );
    assert
      .dom(".spam-warden-submission a")
      .doesNotExist("initial configuration is enabled");
    await click(".spam-warden-submission__preview");
    assert
      .dom(".spam-warden-submission a")
      .hasText(
        i18n("spam_warden.submission.configure"),
        "disabling reporting shows current configuration guidance"
      );
    configured = true;
    await click(".spam-warden-submission__preview");
    assert
      .dom(".spam-warden-submission a")
      .doesNotExist("enabling reporting removes stale guidance");
  });

  test("moderators cannot see reporting controls or identifiers", async function (assert) {
    this.currentUser.setProperties({ admin: false, moderator: true });
    await render(
      <template>
        <ModalContainer />
        <SpamWardenSubmission @userId={{42}} @configured={{true}} />
      </template>
    );
    assert
      .dom(".spam-warden-submission")
      .doesNotExist("reporting is admin-only");
  });

  test("unconfigured reporting links to the relevant site settings", async function (assert) {
    await render(
      <template>
        <ModalContainer />
        <SpamWardenSubmission @userId={{42}} @configured={{false}} />
      </template>
    );
    assert
      .dom(".spam-warden-submission a")
      .hasAttribute(
        "href",
        "/admin/site_settings/category/plugins?filter=spam_warden_submission",
        "configuration has a direct entry point"
      );
    assert
      .dom(".spam-warden-submission-confirmation form")
      .doesNotExist("configuration does not authorize a report");
  });
});
