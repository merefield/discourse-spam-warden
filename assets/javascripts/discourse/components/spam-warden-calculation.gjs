import Component from "@glimmer/component";
import { concat } from "@ember/helper";
import { i18n } from "discourse-i18n";

const signed = (value) => (value > 0 ? `+${value}` : value);

export default class SpamWardenCalculation extends Component {
  get assessment() {
    return this.args.scan?.policy?.assessment;
  }

  get calculation() {
    return this.assessment?.calculation;
  }

  get available() {
    return (
      this.args.scan?.status === "checked" &&
      this.assessment?.scored &&
      Number.isFinite(this.assessment.score)
    );
  }

  get fields() {
    const fields = this.assessment?.external_scoring?.fields || {};
    return ["email", "ip"]
      .filter((field) => fields[field])
      .map((field) => ({ field, ...fields[field] }));
  }

  get confirmedCount() {
    return this.assessment?.local_signals?.confirmed_spam_posts || 0;
  }

  get localCapped() {
    return (
      this.calculation.capped_local <
      this.calculation.posting + this.calculation.additional
    );
  }

  <template>
    <section
      class="spam-warden-calculation spam-warden-evidence__card spam-warden-evidence__risk"
      ...attributes
    >
      <h3 class="spam-warden-evidence__heading">{{i18n
          "spam_warden.dashboard.breakdown"
        }}</h3>
      {{#if this.available}}
        {{#if this.calculation}}
          <dl class="spam-warden-calculation__lines">
            {{#each this.fields as |item|}}
              <div>
                <dt>{{i18n (concat "spam_warden.fields." item.field)}}
                  <span class="spam-warden-calculation__formula">{{i18n
                      "spam_warden.calculation.report_formula"
                      reports=item.reports
                      weight=item.weight
                      cap=item.cap
                      multiplier=item.multiplier
                    }}</span>
                  <span class="spam-warden-calculation__formula">{{i18n
                      (concat "spam_warden.calculation.recency." item.reason)
                      full_days=@scan.policy.external_weights.full_weight_days
                      half_days=@scan.policy.external_weights.half_weight_days
                    }}</span>
                </dt>
                <dd>{{item.points}}</dd>
              </div>
            {{/each}}
            <div><dt>{{i18n "spam_warden.calculation.posting"}}
                {{#if this.assessment.local_signals.enabled}}
                  <span class="spam-warden-calculation__formula">{{i18n
                      "spam_warden.calculation.posting_formula"
                      duplicate=this.assessment.local_signals.duplicate_points
                      burst=this.assessment.local_signals.burst_points
                      cap=this.calculation.posting_cap
                    }}</span>
                {{/if}}
              </dt><dd>{{signed this.calculation.posting}}</dd></div>
            {{#if this.calculation.additional}}<div><dt>{{i18n
                    "spam_warden.additional_evidence"
                  }}</dt><dd>{{signed
                    this.calculation.additional
                  }}</dd></div>{{/if}}
            {{#if this.localCapped}}<div><dt>{{i18n
                    "spam_warden.calculation.local_cap"
                    cap=this.calculation.local_cap
                  }}</dt><dd>{{this.calculation.capped_local}}</dd></div>{{/if}}
            <div><dt>{{i18n "spam_warden.dashboard.reading_adjustment"}}</dt><dd
              >{{signed this.calculation.reading}}</dd></div>
            <div class="spam-warden-calculation__subtotal"><dt>{{i18n
                  "spam_warden.calculation.suspicion"
                }}</dt><dd>{{this.calculation.suspicion}}</dd></div>
            <div><dt>{{i18n "spam_warden.calculation.confirmed"}}
                <span class="spam-warden-calculation__formula">{{i18n
                    "spam_warden.calculation.confirmed_formula"
                    count=this.confirmedCount
                    weight=@scan.policy.weights.confirmed_spam
                  }}</span>
              </dt><dd>{{signed this.calculation.confirmed}}</dd></div>
            <div class="spam-warden-calculation__total"><dt>{{i18n
                  "spam_warden.calculation.total"
                }}</dt><dd>{{i18n
                  "spam_warden.dashboard.percentage"
                  value=this.calculation.total
                }}</dd></div>
          </dl>
          <p class="spam-warden-evidence__caption">{{i18n
              "spam_warden.calculation.saved"
            }}</p>
        {{else}}
          <p>{{i18n "spam_warden.calculation.legacy_summary"}}</p>
          <dl class="spam-warden-calculation__lines">
            <div><dt>{{i18n "spam_warden.dashboard.external_points"}}</dt><dd
              >{{this.assessment.base_score}}</dd></div>
            <div><dt>{{i18n "spam_warden.dashboard.reading_adjustment"}}</dt><dd
              >{{signed this.assessment.engagement.adjustment}}</dd></div>
            {{#if this.assessment.local_signals.enabled}}<div><dt>{{i18n
                    "spam_warden.dashboard.local_adjustment"
                  }}</dt><dd>{{signed
                    this.assessment.local_signals.adjustment
                  }}</dd></div>{{/if}}
            {{#if this.assessment.additional_points}}<div><dt>{{i18n
                    "spam_warden.additional_evidence"
                  }}</dt><dd>{{signed
                    this.assessment.additional_points
                  }}</dd></div>{{/if}}
            <div class="spam-warden-calculation__total"><dt>{{i18n
                  "spam_warden.calculation.saved_total"
                }}</dt><dd>{{i18n
                  "spam_warden.dashboard.percentage"
                  value=this.assessment.score
                }}</dd></div>
          </dl>
          {{#if this.assessment.local_signals.enabled}}
            <p class="spam-warden-evidence__caption">{{i18n
                "spam_warden.dashboard.local_points"
                duplicate=this.assessment.local_signals.duplicate_points
                burst=this.assessment.local_signals.burst_points
                posting=this.assessment.local_signals.posting_points
                history=this.assessment.local_signals.history_points
                total=this.assessment.local_signals.adjustment
              }}</p>
          {{/if}}
        {{/if}}
        {{#if this.assessment.additional_evidence.length}}
          <ul>{{#each this.assessment.additional_evidence as |entry|}}<li
              >{{entry.label}}: {{entry.points}}</li>{{/each}}</ul>
        {{/if}}
      {{else}}
        <p>{{i18n "spam_warden.dashboard.unscored_help"}}</p>
      {{/if}}
    </section>
  </template>
}
