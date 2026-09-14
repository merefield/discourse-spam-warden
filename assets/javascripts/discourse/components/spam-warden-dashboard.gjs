import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { concat, fn, hash } from "@ember/helper";
import { action } from "@ember/object";
import { service } from "@ember/service";
import Form from "discourse/components/form";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import getURL from "discourse/lib/get-url";
import UserChooser from "discourse/select-kit/components/user-chooser";
import { not } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import DPageSubheader from "discourse/ui-kit/d-page-subheader";
import { i18n } from "discourse-i18n";
import SpamWardenEvidence from "./spam-warden-evidence";
import SpamWardenStatus from "./spam-warden-status";

export default class SpamWardenDashboard extends Component {
  @service a11y;

  @tracked result;
  @tracked message;
  @tracked testing = false;
  @tracked selectedUsernames = [];

  @action
  selectUser(setValue, usernames, users) {
    this.selectedUsernames = usernames;
    setValue(users?.[0]?.id || null);
  }

  get healthLabel() {
    return i18n(
      `spam_warden.health.${this.args.model.health.status || "untested"}`
    );
  }

  @action
  async testConnection() {
    this.testing = true;
    try {
      const result = await ajax("/admin/plugins/discourse-spam-warden/test", {
        type: "POST",
      });
      this.message = i18n(
        result.status === "checked"
          ? "spam_warden.test_success"
          : "spam_warden.test_failed"
      );
      this.a11y.announce(this.message);
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.testing = false;
    }
  }

  @action
  async checkUser(data) {
    const result = await ajax("/admin/plugins/discourse-spam-warden/check", {
      type: "POST",
      data,
    });
    this.result = result.scan;
    this.message = i18n(
      result.scan ? "spam_warden.check_complete" : "spam_warden.exempt"
    );
    this.a11y.announce(this.message);
  }

  <template>
    <div
      class="spam-warden-dashboard admin-config-page__main-area"
      ...attributes
    >
      <DPageSubheader
        @titleLabel={{i18n "spam_warden.activity"}}
        @descriptionLabel={{i18n "spam_warden.description"}}
      />
      <p>{{i18n "spam_warden.setup_help"}}</p>
      <p>{{i18n "spam_warden.mode_label"}}
        {{i18n (concat "spam_warden.modes." @model.mode)}}</p>
      {{#unless @model.enabled}}<p>{{i18n
            "spam_warden.disabled"
          }}</p>{{/unless}}
      <p>{{this.healthLabel}}</p>
      {{#if @model.health.last_success_at}}
        <p>{{i18n
            "spam_warden.last_success"
            date=@model.health.last_success_at
          }}</p>
      {{/if}}
      <DButton
        @label="spam_warden.test"
        @action={{this.testConnection}}
        @disabled={{this.testing}}
        class="btn-default"
      />
      {{#if this.message}}<p>{{this.message}}</p>{{/if}}
      <DPageSubheader @titleLabel={{i18n "spam_warden.check_user"}} />
      <Form @onSubmit={{this.checkUser}} as |form|>
        <form.Field
          @name="user_id"
          @title={{i18n "spam_warden.user"}}
          @type="custom"
          @validation="required"
          as |field|
        >
          <field.Control>
            <UserChooser
              @value={{this.selectedUsernames}}
              @onChange={{fn this.selectUser field.set}}
              @options={{hash maximum=1 excludeCurrentUser=false}}
            />
          </field.Control>
        </form.Field>
        <form.Submit
          @label="spam_warden.check_user"
          @disabled={{not @model.enabled}}
        />
      </Form>
      {{#if this.result}}<SpamWardenEvidence @scan={{this.result}} />{{/if}}
      <DPageSubheader @titleLabel={{i18n "spam_warden.recent"}} />
      {{#if @model.scans.length}}
        <table class="d-table">
          <thead class="d-table__header"><tr class="d-table__row">
              <th>{{i18n "spam_warden.user"}}</th><th>{{i18n
                  "spam_warden.evidence"
                }}</th><th>{{i18n "spam_warden.action"}}</th><th>{{i18n
                  "spam_warden.details"
                }}</th>
            </tr></thead>
          <tbody class="d-table__body">
            {{#each @model.scans as |scan|}}
              <tr class="d-table__row">
                <td class="d-table__cell --overview"><a
                    href={{getURL
                      (concat
                        "/admin/users/"
                        scan.user_id
                        "/"
                        scan.username
                        "?spamWarden=true#spam-warden"
                      )
                    }}
                  >{{scan.username}}</a></td>
                <td class="d-table__cell --detail"><div
                    class="d-table__mobile-label"
                  >{{i18n "spam_warden.evidence"}}</div><SpamWardenStatus
                    @decision={{scan.decision}}
                    @status={{scan.status}}
                  /></td>
                <td class="d-table__cell --detail"><div
                    class="d-table__mobile-label"
                  >{{i18n "spam_warden.action"}}</div>{{i18n
                    (concat "spam_warden.actions." scan.action_taken)
                  }}</td>
                <td class="d-table__cell --detail">
                  <div class="d-table__mobile-label">{{i18n
                      "spam_warden.details"
                    }}</div>
                  <details><summary>{{i18n
                        "spam_warden.details"
                      }}</summary><SpamWardenEvidence
                      @scan={{scan}}
                    /></details>
                  {{#if scan.reviewable_id}}<a
                      href={{getURL (concat "/review/" scan.reviewable_id)}}
                    >{{i18n "spam_warden.open_review"}}</a>{{/if}}
                </td>
              </tr>
            {{/each}}
          </tbody>
        </table>
      {{else}}
        <p>{{i18n "spam_warden.empty"}}</p>
      {{/if}}
    </div>
  </template>
}
