import Component from "@glimmer/component";
import { concat } from "@ember/helper";
import { service } from "@ember/service";
import getURL from "discourse/lib/get-url";
import { and, eq } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import DRelativeDate from "discourse/ui-kit/d-relative-date";
import { i18n } from "discourse-i18n";

export default class SpamWardenAiEvidence extends Component {
  @service currentUser;

  <template>
    {{#if this.currentUser.admin}}
      {{#if @evidence}}
        <section class="spam-warden-ai-evidence" ...attributes>
          <h3>{{i18n "spam_warden.ai.title"}}</h3>
          <p>{{i18n "spam_warden.ai.description"}}</p>
          <DButton
            @label="spam_warden.ai.refresh"
            @action={{@onRefresh}}
            @disabled={{@loading}}
            class="btn-default"
          />
          {{#each @evidence.entries as |entry|}}
            <article class="spam-warden-ai-evidence__entry">
              <h4>{{i18n (concat "spam_warden.ai.outcome." entry.outcome)}}</h4>
              <p>{{i18n
                  (if
                    entry.is_spam
                    "spam_warden.ai.spam"
                    "spam_warden.ai.not_spam"
                  )
                }}</p>
              {{#if entry.reason}}<p
                  class="spam-warden-ai-evidence__reason"
                >{{entry.reason}}</p>{{/if}}
              <p>{{i18n "spam_warden.ai.checked"}}
                <DRelativeDate @date={{entry.checked_at}} /></p>
              {{#if entry.has_error}}<p>{{i18n
                    "spam_warden.ai.error"
                  }}</p>{{/if}}
              <div class="spam-warden-ai-evidence__actions">
                <a href={{getURL entry.post_url}}>{{i18n
                    "spam_warden.ai.post"
                  }}</a>
                {{#if entry.reviewable_id}}
                  <a
                    href={{getURL (concat "/review/" entry.reviewable_id)}}
                  >{{i18n "spam_warden.ai.review"}}</a>
                {{/if}}
                {{#if (and @canReport (eq entry.outcome "confirmed"))}}
                  <DButton
                    @label="spam_warden.ai.report"
                    @action={{@onReport}}
                    class="btn-default"
                  />
                {{/if}}
              </div>
            </article>
          {{else}}
            <p>{{i18n "spam_warden.ai.empty"}}</p>
          {{/each}}
          <p class="spam-warden-ai-evidence__scope">{{i18n
              "spam_warden.ai.scope"
            }}</p>
        </section>
      {{/if}}
    {{/if}}
  </template>
}
