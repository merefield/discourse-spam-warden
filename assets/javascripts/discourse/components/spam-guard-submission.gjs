import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { concat } from "@ember/helper";
import { action } from "@ember/object";
import didUpdate from "@ember/render-modifiers/modifiers/did-update";
import { service } from "@ember/service";
import Form from "discourse/components/form";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import getURL from "discourse/lib/get-url";
import DButton from "discourse/ui-kit/d-button";
import DModal from "discourse/ui-kit/d-modal";
import DRelativeDate from "discourse/ui-kit/d-relative-date";
import { i18n } from "discourse-i18n";

export default class SpamGuardSubmission extends Component {
  @service currentUser;
  @service a11y;

  @tracked result;
  @tracked busy = false;

  get configured() {
    return this.result ? this.result.configured : this.args.configured;
  }

  get report() {
    return this.result ? this.result.submission : this.args.submission;
  }

  get statusText() {
    return i18n(`spam_guard.submission.status.${this.report.status}`);
  }

  get statusHelp() {
    return i18n(`spam_guard.submission.help.${this.report.status}`);
  }

  get settingsUrl() {
    return getURL(
      "/admin/site_settings/category/plugins?filter=spam_guard_submission"
    );
  }

  @action
  reset() {
    this.result = undefined;
    this.busy = false;
  }

  @action
  previewRequested() {
    if (this.args.previewRequest > 0 && !this.busy) {
      this.preview();
    }
  }

  @action
  async preview() {
    const userId = this.args.userId;
    this.busy = true;
    try {
      const result = await ajax(
        `/admin/plugins/discourse-spam-guard/accounts/${userId}/submission.json`
      );
      if (
        !this.isDestroying &&
        !this.isDestroyed &&
        this.args.userId === userId
      ) {
        this.result = result;
      }
    } catch (error) {
      if (
        !this.isDestroying &&
        !this.isDestroyed &&
        this.args.userId === userId
      ) {
        popupAjaxError(error);
      }
    } finally {
      if (
        !this.isDestroying &&
        !this.isDestroyed &&
        this.args.userId === userId
      ) {
        this.busy = false;
      }
    }
  }

  @action
  closePreview() {
    if (!this.busy) {
      this.result = undefined;
    }
  }

  @action
  async submit(data) {
    const userId = this.args.userId;
    const token = this.result.preview.token;
    this.busy = true;
    try {
      const response = await ajax(
        `/admin/plugins/discourse-spam-guard/accounts/${userId}/submission`,
        {
          type: "POST",
          data: { token, confirmed: data.confirmed },
        }
      );
      if (
        !this.isDestroying &&
        !this.isDestroyed &&
        this.args.userId === userId
      ) {
        this.result = {
          submission: response.submission,
          preview: null,
          configured: true,
        };
        this.a11y.announce(i18n("spam_guard.submission.queued"));
      }
    } catch (error) {
      if (
        !this.isDestroying &&
        !this.isDestroyed &&
        this.args.userId === userId
      ) {
        popupAjaxError(error);
      }
    } finally {
      if (
        !this.isDestroying &&
        !this.isDestroyed &&
        this.args.userId === userId
      ) {
        this.busy = false;
      }
    }
  }

  <template>
    {{#if this.currentUser.admin}}
      <section
        class="spam-guard-submission"
        {{didUpdate this.reset @userId}}
        {{didUpdate this.previewRequested @previewRequest}}
        ...attributes
      >
        <h3>{{i18n "spam_guard.submission.title"}}</h3>
        <p>{{i18n "spam_guard.submission.description"}}</p>
        {{#unless this.configured}}
          <p><a href={{this.settingsUrl}}>{{i18n
                "spam_guard.submission.configure"
              }}</a></p>
        {{/unless}}
        {{#if this.report}}
          <p class="spam-guard-submission__status" role="status"><strong
            >{{this.statusText}}</strong></p>
          <p>{{this.statusHelp}}</p>
          <p>{{i18n
              "spam_guard.submission.attempts"
              count=this.report.attempts
            }}</p>
          {{#if this.report.events}}
            <details>
              <summary>{{i18n "spam_guard.submission.history"}}</summary>
              <ul>
                {{#each this.report.events as |event|}}
                  <li><DRelativeDate @date={{event.at}} />
                    ·
                    {{i18n
                      (concat "spam_guard.submission.status." event.status)
                    }}
                    ·
                    {{#if event.actor_username}}
                      <a
                        href={{getURL
                          (concat
                            "/admin/users/"
                            event.actor_id
                            "/"
                            event.actor_username
                          )
                        }}
                      >{{i18n
                          "spam_guard.submission.actor_username"
                          username=event.actor_username
                        }}</a>
                    {{else}}
                      {{i18n "spam_guard.submission.actor" id=event.actor_id}}
                    {{/if}}</li>
                {{/each}}
              </ul>
            </details>
          {{/if}}
        {{/if}}
        <DButton
          @label={{if
            this.report
            "spam_guard.submission.refresh"
            "spam_guard.submission.preview"
          }}
          @action={{this.preview}}
          @disabled={{this.busy}}
          class="btn-default spam-guard-submission__preview"
        />
        {{#if this.result.preview}}
          <DModal
            @title={{i18n "spam_guard.submission.preview_title"}}
            @closeModal={{this.closePreview}}
            @dismissable={{if this.busy false true}}
            @submitOnEnter={{false}}
            class="spam-guard-submission-confirmation"
          >
            <:body>
              <p>{{i18n "spam_guard.submission.disclosure"}}</p>
              <dl class="spam-guard-submission-confirmation__fields">
                <div><dt>{{i18n "spam_guard.submission.destination"}}</dt><dd
                  >{{this.result.preview.destination}}</dd></div>
                <div><dt>{{i18n "spam_guard.submission.username"}}</dt><dd
                  >{{this.result.preview.username}}</dd></div>
                <div><dt>{{i18n "spam_guard.submission.email"}}</dt><dd
                  >{{this.result.preview.email}}</dd></div>
                <div><dt>{{i18n "spam_guard.submission.ip"}}</dt><dd
                  >{{this.result.preview.ip_address}}</dd></div>
              </dl>
              <h3>{{i18n "spam_guard.submission.evidence"}}</h3>
              <p>{{i18n "spam_guard.submission.evidence_description"}}</p>
              <pre
                class="spam-guard-submission-confirmation__evidence"
              >{{this.result.preview.evidence}}</pre>
              <p>{{i18n "spam_guard.submission.authentication"}}</p>
              <p>{{i18n "spam_guard.submission.response_format"}}</p>
              <Form @onSubmit={{this.submit}} as |form|>
                <form.Field
                  @name="confirmed"
                  @title={{i18n "spam_guard.submission.confirm"}}
                  @type="checkbox"
                  @validation="accepted"
                  as |field|
                >
                  <field.Control />
                </form.Field>
                <form.Submit
                  @label="spam_guard.submission.submit"
                  @disabled={{this.busy}}
                />
              </Form>
            </:body>
            <:footer>
              <DButton
                @label="cancel"
                @action={{this.closePreview}}
                @disabled={{this.busy}}
                class="btn-default spam-guard-submission-confirmation__cancel"
              />
            </:footer>
          </DModal>
        {{else if this.result.configured}}
          {{#unless this.report}}
            <p class="spam-guard-submission__ineligible">{{i18n
                "spam_guard.submission.ineligible"
              }}</p>
          {{/unless}}
        {{/if}}
      </section>
    {{/if}}
  </template>
}
