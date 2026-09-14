import Component from "@glimmer/component";
import { concat } from "@ember/helper";
import { notEq } from "discourse/truth-helpers";
import DRelativeDate from "discourse/ui-kit/d-relative-date";
import dFormatDuration from "discourse/ui-kit/helpers/d-format-duration";
import dNumber from "discourse/ui-kit/helpers/d-number";
import { i18n } from "discourse-i18n";
import SpamWardenCalculation from "./spam-warden-calculation";
import SpamWardenRiskScore from "./spam-warden-risk-score";
import SpamWardenStatus from "./spam-warden-status";

const suppliedValue = (value) =>
  value ?? i18n("spam_warden.dashboard.not_supplied");

export default class SpamWardenEvidence extends Component {
  get hasScore() {
    const assessment = this.args.scan?.policy?.assessment;
    return (
      this.args.scan?.status === "checked" &&
      assessment?.scored &&
      Number.isFinite(assessment.score) &&
      assessment.score >= 0 &&
      assessment.score <= 100
    );
  }

  get summary() {
    if (!this.hasScore) {
      return i18n("spam_warden.dashboard.unscored_help");
    }
    const calculation = this.args.scan.policy.assessment.calculation;
    if (!calculation) {
      return i18n("spam_warden.calculation.legacy_summary");
    }
    if (calculation.confirmed > 0) {
      return i18n("spam_warden.calculation.confirmed_summary", {
        suspicion: calculation.suspicion,
        confirmed: calculation.confirmed,
      });
    }
    const points = this.args.scan.policy.assessment.external_scoring.points;
    return i18n("spam_warden.calculation.summary", {
      email: points.email,
      ip: points.ip,
      adjustment: calculation.suspicion - calculation.external,
    });
  }

  <template>
    <div class="spam-warden-evidence" ...attributes>
      {{#if @scan}}
        <header class="spam-warden-evidence__header">
          <SpamWardenRiskScore
            @exempt={{@exempt}}
            @score={{@scan.policy.assessment.score}}
            @scored={{@scan.policy.assessment.scored}}
            @decision={{@scan.decision}}
            @status={{@scan.status}}
          />
          <div class="spam-warden-evidence__overview">
            <h3 class="spam-warden-evidence__title">{{#if @scan.username}}{{i18n
                  "spam_warden.dashboard.account"
                  username=@scan.username
                }}{{else}}{{i18n
                  "spam_warden.dashboard.assessment"
                }}{{/if}}</h3>
            <p class="spam-warden-evidence__summary">{{this.summary}}</p>
            <dl class="spam-warden-evidence__facts">
              <div><dt>{{i18n "spam_warden.action"}}</dt><dd>{{i18n
                    (concat "spam_warden.actions." @scan.action_taken)
                  }}</dd></div>
              <div><dt>{{i18n "spam_warden.dashboard.checked"}}</dt><dd
                ><DRelativeDate @date={{@scan.created_at}} /></dd></div>
              {{#if @scan.source}}<div><dt>{{i18n
                      "spam_warden.dashboard.source"
                    }}</dt><dd>{{i18n
                      (concat "spam_warden.dashboard.sources." @scan.source)
                    }}</dd></div>{{/if}}
            </dl>
            {{#if @scan.error_code}}<p
                class="spam-warden-evidence__notice"
              >{{i18n
                  (concat "spam_warden.errors." @scan.error_code)
                }}</p>{{/if}}
          </div>
        </header>

        <div class="spam-warden-evidence__layout">
          <SpamWardenCalculation @scan={{@scan}} />
          <div class="spam-warden-evidence__body">
            <section class="spam-warden-evidence__provider">
              <div class="spam-warden-evidence__section-header">
                <h3 class="spam-warden-evidence__heading">{{i18n
                    "spam_warden.dashboard.provider"
                  }}</h3>
                {{#if @scan.policy.assessment}}
                  {{#if
                    (notEq
                      @scan.decision @scan.policy.assessment.external_decision
                    )
                  }}
                    <SpamWardenStatus
                      @decision={{@scan.policy.assessment.external_decision}}
                      @status={{@scan.status}}
                    />
                  {{/if}}
                {{/if}}
              </div>
              <div class="spam-warden-evidence__signals">
                {{#each @scan.evidence as |item|}}
                  <div class="spam-warden-evidence__signal">
                    <strong>{{i18n
                        (concat "spam_warden.fields." item.field)
                      }}</strong>
                    <span class="spam-warden-evidence__report-count">{{i18n
                        "spam_warden.reports"
                        count=item.frequency
                      }}</span>
                    {{#if item.appears}}
                      <dl class="spam-warden-evidence__signal-details">
                        <div><dt>{{i18n
                              "spam_warden.dashboard.confidence"
                            }}</dt><dd>{{suppliedValue
                              item.confidence
                            }}</dd></div>
                        <div><dt>{{i18n
                              "spam_warden.dashboard.last_report"
                            }}</dt><dd>{{#if item.last_seen}}<DRelativeDate
                                @date={{item.last_seen}}
                              />{{else}}{{i18n
                                "spam_warden.dashboard.not_supplied"
                              }}{{/if}}</dd></div>
                      </dl>
                    {{/if}}
                  </div>
                {{else}}
                  <p class="spam-warden-evidence__caption">{{i18n
                      "spam_warden.dashboard.no_provider_evidence"
                    }}</p>
                {{/each}}
              </div>
            </section>

            {{#if @scan.policy.assessment}}
              <section
                class="spam-warden-evidence__card spam-warden-evidence__engagement"
              >
                <h3 class="spam-warden-evidence__heading">{{i18n
                    "spam_warden.dashboard.reading"
                  }}</h3>
                {{#if @scan.policy.assessment.engagement.available}}
                  <dl class="spam-warden-evidence__metrics">
                    <div><dt>{{i18n "spam_warden.dashboard.topics"}}</dt><dd
                      >{{dNumber
                          @scan.policy.assessment.engagement.topics_viewed
                        }}</dd></div>
                    <div><dt>{{i18n "spam_warden.dashboard.posts"}}</dt><dd
                      >{{dNumber
                          @scan.policy.assessment.engagement.posts_read
                        }}</dd></div>
                    <div><dt>{{i18n "spam_warden.dashboard.time"}}</dt><dd
                      >{{dFormatDuration
                          @scan.policy.assessment.engagement.reading_seconds
                        }}</dd></div>
                    <div><dt>{{i18n "spam_warden.dashboard.visits"}}</dt><dd
                      >{{dNumber
                          @scan.policy.assessment.engagement.days_visited
                        }}</dd></div>
                  </dl>
                {{/if}}
                <p class="spam-warden-evidence__caption">{{i18n
                    (concat
                      "spam_warden.engagement.levels."
                      @scan.policy.assessment.engagement.level
                    )
                  }}</p>
              </section>

              {{#if @scan.policy.assessment.local_signals.enabled}}
                <section class="spam-warden-evidence__card">
                  <h3 class="spam-warden-evidence__heading">{{i18n
                      "spam_warden.dashboard.local_signals"
                    }}</h3>
                  <dl class="spam-warden-evidence__metrics">
                    <div><dt>{{i18n "spam_warden.dashboard.duplicates"}}</dt><dd
                      >{{dNumber
                          @scan.policy.assessment.local_signals.duplicate_posts
                        }}</dd></div>
                    <div><dt>{{i18n
                          "spam_warden.dashboard.burst_posts"
                        }}</dt><dd>{{dNumber
                          @scan.policy.assessment.local_signals.burst_posts
                        }}</dd></div>
                    <div><dt>{{i18n
                          "spam_warden.dashboard.burst_topics"
                        }}</dt><dd>{{dNumber
                          @scan.policy.assessment.local_signals.burst_topics
                        }}</dd></div>
                    <div><dt>{{i18n
                          "spam_warden.dashboard.confirmed_spam"
                        }}</dt><dd>{{dNumber
                          @scan.policy.assessment.local_signals.confirmed_spam_posts
                        }}</dd></div>
                  </dl>
                </section>
              {{/if}}
            {{/if}}
            {{yield}}
          </div>
        </div>
        <details class="spam-warden-evidence__help">
          <summary>{{i18n "spam_warden.calculation.how"}}</summary>
          {{#if @scan.policy.assessment.calculation}}
            <p>{{i18n "spam_warden.calculation.method"}}</p>
            <p>{{i18n
                "spam_warden.calculation.recency_help"
                full_days=@scan.policy.external_weights.full_weight_days
                half_days=@scan.policy.external_weights.half_weight_days
              }}</p>
          {{else}}
            {{#if @scan.policy.weights}}
              <p>{{i18n
                  "spam_warden.dashboard.configured_weights"
                  spam_points=@scan.policy.weights.confirmed_spam
                  cap=@scan.policy.weights.local_cap
                }}</p>
            {{/if}}
          {{/if}}
          <p>{{i18n "spam_warden.dashboard.local_help"}}</p>
          <p>{{i18n "spam_warden.dashboard.score_help"}}</p>
          <p>{{i18n "spam_warden.evidence_help"}}</p>
        </details>
      {{else}}
        {{#if @exempt}}<SpamWardenRiskScore @exempt={{true}} />{{/if}}
        <p>{{i18n "spam_warden.no_evidence"}}</p>
        {{yield}}
      {{/if}}
    </div>
  </template>
}
