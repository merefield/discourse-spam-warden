import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { concat } from "@ember/helper";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import didUpdate from "@ember/render-modifiers/modifiers/did-update";
import { ajax } from "discourse/lib/ajax";
import getURL from "discourse/lib/get-url";
import DButton from "discourse/ui-kit/d-button";
import DRelativeDate from "discourse/ui-kit/d-relative-date";
import { i18n } from "discourse-i18n";

const scoreLabel = (value) => value ?? i18n("spam_warden.related.unassessed");

export default class SpamWardenRelatedAccounts extends Component {
  @tracked data;
  @tracked busy = false;
  @tracked failed = false;
  #request = 0;

  @action
  refresh() {
    return this.#load(false);
  }

  @action
  more() {
    return this.#load(true);
  }

  async #load(append) {
    const request = ++this.#request;
    const userId = this.args.userId;
    const previous = append ? this.data : null;
    if (!append) {
      this.data = null;
    }
    this.busy = true;
    this.failed = false;
    try {
      const data = await ajax(
        `/admin/plugins/discourse-spam-warden/accounts/${userId}/related.json`,
        {
          data: { after_id: previous?.next_after_id || 0 },
        }
      );
      if (
        !this.isDestroyed &&
        !this.isDestroying &&
        request === this.#request &&
        userId === this.args.userId
      ) {
        this.data = {
          ...data,
          accounts: [...(previous?.accounts || []), ...data.accounts],
        };
      }
    } catch {
      if (
        !this.isDestroyed &&
        !this.isDestroying &&
        request === this.#request
      ) {
        this.failed = true;
      }
    } finally {
      if (
        !this.isDestroyed &&
        !this.isDestroying &&
        request === this.#request
      ) {
        this.busy = false;
      }
    }
  }

  <template>
    <section
      class="spam-warden-related spam-warden-evidence__card"
      {{didInsert this.refresh}}
      {{didUpdate this.refresh @userId @scanId @exempt}}
    >
      <div class="spam-warden-evidence__section-header">
        <h3 class="spam-warden-evidence__heading">{{i18n
            "spam_warden.related.title"
          }}</h3>
        <DButton
          @action={{this.refresh}}
          @disabled={{this.busy}}
          @label="spam_warden.related.refresh"
          @icon="arrows-rotate"
          class="btn-flat"
        />
      </div>
      {{#if this.busy}}<p role="status">{{i18n "loading"}}</p>{{/if}}
      {{#if this.failed}}<p role="alert">{{i18n
            "spam_warden.related.failed"
          }}</p>{{/if}}
      {{#if this.data}}
        <p>{{i18n
            "spam_warden.related.summary"
            count=this.data.total
            days=this.data.days
            threshold=this.data.threshold
          }}</p>
        <p class="spam-warden-evidence__caption">{{i18n
            "spam_warden.related.live_help"
          }}</p>
        {{#if this.data.eligible}}
          {{#if this.data.enabled}}
            {{#if this.data.own_qualifies}}<p>{{i18n
                  "spam_warden.related.own_qualifies"
                  score=this.data.own_score
                }}</p>{{/if}}
          {{else}}<p>{{i18n "spam_warden.related.disabled"}}</p>{{/if}}
        {{else}}<p>{{i18n "spam_warden.related.excluded"}}</p>{{/if}}
        {{#if this.data.saved_at}}
          <p>{{i18n
              "spam_warden.related.saved"
              points=(scoreLabel this.data.saved_points)
            }}
            <DRelativeDate @date={{this.data.saved_at}} /></p>
        {{/if}}
        {{#if this.data.accounts.length}}
          <table class="d-table">
            <thead class="d-table__header"><tr class="d-table__row">
                <th class="d-table__header-cell">{{i18n
                    "spam_warden.related.account"
                  }}</th>
                <th class="d-table__header-cell">{{i18n
                    "spam_warden.related.score"
                  }}</th>
                <th class="d-table__header-cell">{{i18n
                    "spam_warden.related.connections"
                  }}</th>
              </tr></thead>
            <tbody class="d-table__body">
              {{#each this.data.accounts key="id" as |account|}}
                <tr class="d-table__row">
                  <td class="d-table__cell --overview">
                    <a
                      href={{getURL
                        (concat
                          "/admin/users/"
                          account.id
                          "/"
                          account.username
                          "?spamWarden=true#spam-warden"
                        )
                      }}
                    >{{account.username}}</a>
                    {{#if account.qualifies}}<div>{{i18n
                          "spam_warden.related.qualifies"
                        }}</div>{{/if}}
                  </td>
                  <td class="d-table__cell --detail">
                    <div class="d-table__mobile-label">{{i18n
                        "spam_warden.related.score"
                      }}</div>
                    {{scoreLabel account.independent_score}}
                    {{#if account.checked_at}}<div><DRelativeDate
                          @date={{account.checked_at}}
                        /></div>{{/if}}
                  </td>
                  <td class="d-table__cell --detail">
                    <div class="d-table__mobile-label">{{i18n
                        "spam_warden.related.connections"
                      }}</div>
                    {{#each account.connection_types as |connection|}}<div
                      >{{i18n
                          "spam_warden.related.connection"
                          source=(i18n
                            (concat
                              "spam_warden.related.sources." connection.source
                            )
                          )
                          peer_source=(i18n
                            (concat
                              "spam_warden.related.sources."
                              connection.peer_source
                            )
                          )
                        }}</div>{{/each}}
                    <details><summary>{{i18n
                          "spam_warden.related.show_connections"
                          count=account.connections.length
                        }}</summary>
                      <ul>{{#each account.connections as |connection|}}<li>
                            <strong>{{connection.ip}}</strong>
                            <div>{{i18n
                                "spam_warden.related.connection"
                                source=(i18n
                                  (concat
                                    "spam_warden.related.sources."
                                    connection.source
                                  )
                                )
                                peer_source=(i18n
                                  (concat
                                    "spam_warden.related.sources."
                                    connection.peer_source
                                  )
                                )
                              }}</div>
                            <div>{{i18n "spam_warden.related.this_account"}}
                              <DRelativeDate @date={{connection.at}} /></div>
                            <div>{{i18n "spam_warden.related.other_account"}}
                              <DRelativeDate
                                @date={{connection.peer_at}}
                              /></div>
                          </li>{{/each}}</ul>
                    </details>
                  </td>
                </tr>
              {{/each}}
            </tbody>
          </table>
        {{else}}<p>{{i18n "spam_warden.related.empty"}}</p>{{/if}}
        {{#if this.data.next_after_id}}<DButton
            @action={{this.more}}
            @disabled={{this.busy}}
            @label="spam_warden.related.more"
            class="btn-default"
          />{{/if}}
        <p class="spam-warden-evidence__caption">{{i18n
            "spam_warden.related.date_help"
          }}</p>
      {{/if}}
    </section>
  </template>
}
