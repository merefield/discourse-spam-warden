import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import didUpdate from "@ember/render-modifiers/modifiers/did-update";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import DButton from "discourse/ui-kit/d-button";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";
import SpamWardenAiEvidence from "./spam-warden-ai-evidence";
import SpamWardenEvidence from "./spam-warden-evidence";
import SpamWardenSubmission from "./spam-warden-submission";

export default class SpamWardenUser extends Component {
  @service currentUser;
  @service a11y;
  @service router;

  @tracked reportRequest = 0;
  @tracked state;
  @tracked busy = false;
  @tracked expanded = false;
  @tracked loading = false;

  get visible() {
    return this.currentUser?.admin;
  }

  get canManage() {
    return !this.args.user.admin && !this.args.user.moderator;
  }

  get openRequested() {
    const value = this.router.currentRoute?.queryParams?.spamWarden;
    return value === true || value === "true";
  }

  @action
  openFromLink(element) {
    const userId = this.args.user.id;
    if (this.stateUserId !== userId) {
      this.stateUserId = userId;
      this.state = undefined;
      this.reportRequest = 0;
      this.expanded = false;
      this.openedForUserId = null;
    }
    if (
      this.visible &&
      this.openedForUserId !== userId &&
      (this.openRequested || window.location.hash === "#spam-warden")
    ) {
      this.openedForUserId = userId;
      this.expanded = true;
      this.load().then(() => {
        if (
          !this.isDestroyed &&
          !this.isDestroying &&
          this.args.user.id === userId
        ) {
          element.scrollIntoView({ block: "start" });
        }
      });
    }
  }

  @action
  async load() {
    const userId = this.args.user.id;
    this.loading = true;
    try {
      const state = await ajax(
        `/admin/plugins/discourse-spam-warden/accounts/${userId}.json`
      );
      if (
        !this.isDestroyed &&
        !this.isDestroying &&
        this.args.user.id === userId
      ) {
        this.state = state;
      }
    } catch (error) {
      popupAjaxError(error);
    } finally {
      if (
        !this.isDestroyed &&
        !this.isDestroying &&
        this.args.user.id === userId
      ) {
        this.loading = false;
      }
    }
  }

  @action
  async toggleExpanded() {
    this.expanded = !this.expanded;
    if (this.expanded && !this.state && !this.loading) {
      await this.load();
    }
  }

  @action
  async check() {
    this.busy = true;
    try {
      await ajax("/admin/plugins/discourse-spam-warden/check", {
        type: "POST",
        data: { user_id: this.args.user.id },
      });
      await this.load();
      this.a11y.announce(i18n("spam_warden.check_complete"));
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.busy = false;
    }
  }

  @action
  openReport() {
    this.reportRequest++;
  }

  @action
  async toggleException() {
    this.busy = true;
    try {
      await ajax(
        `/admin/plugins/discourse-spam-warden/accounts/${this.args.user.id}/exception`,
        {
          type: "PUT",
          data: { allowed: !this.state.allowed },
        }
      );
      await this.load();
      this.a11y.announce(i18n("spam_warden.exception_updated"));
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.busy = false;
    }
  }

  <template>
    {{#if this.visible}}
      <div
        class="spam-warden-user"
        id="spam-warden"
        {{didInsert this.openFromLink}}
        {{didUpdate this.openFromLink @user.id this.openRequested}}
        ...attributes
      >
        <h2 class="spam-warden-user__header">
          <button
            type="button"
            title={{i18n
              (if
                this.expanded
                "spam_warden.collapse_dashboard"
                "spam_warden.expand_dashboard"
              )
            }}
            aria-expanded={{if this.expanded "true" "false"}}
            aria-controls="spam-warden-dashboard"
            class="spam-warden-user__toggle"
            {{on "click" this.toggleExpanded}}
          >
            <span class="spam-warden-user__title">{{i18n
                "spam_warden.title"
              }}</span>
            {{dIcon (if this.expanded "chevron-up" "chevron-down")}}
          </button>
        </h2>
        <div id="spam-warden-dashboard" hidden={{if this.expanded false true}}>
          {{#if this.expanded}}
            {{#if this.loading}}<p>{{i18n "loading"}}</p>{{/if}}
            {{#if this.state}}
              {{#if this.canManage}}
                <div class="spam-warden-user__actions">
                  {{#if this.state.enabled}}
                    <DButton
                      @label="spam_warden.recheck_account"
                      @action={{this.check}}
                      @disabled={{this.busy}}
                      class="btn-default"
                    />
                  {{/if}}
                  <DButton
                    @label={{if
                      this.state.allowed
                      "spam_warden.remove_exception"
                      "spam_warden.allow"
                    }}
                    @action={{this.toggleException}}
                    @disabled={{this.busy}}
                    class="btn-default spam-warden-user__exception"
                  />
                </div>
                {{#if this.state.allowed}}<p>{{i18n
                      "spam_warden.exempt"
                    }}</p>{{/if}}
              {{/if}}

              <SpamWardenEvidence
                @scan={{this.state.scan}}
                @exempt={{this.state.allowed}}
              >
                <SpamWardenAiEvidence
                  @evidence={{this.state.ai_evidence}}
                  @canReport={{this.canManage}}
                  @onRefresh={{this.load}}
                  @loading={{this.loading}}
                  @onReport={{this.openReport}}
                />
              </SpamWardenEvidence>

              {{#if this.canManage}}
                <SpamWardenSubmission
                  @previewRequest={{this.reportRequest}}
                  @userId={{@user.id}}
                  @configured={{this.state.submission_configured}}
                  @submission={{this.state.submission}}
                />
              {{/if}}
            {{/if}}
          {{/if}}
        </div>
      </div>
    {{/if}}
  </template>
}
