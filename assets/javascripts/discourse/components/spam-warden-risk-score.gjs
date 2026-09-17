import Component from "@glimmer/component";
import dConcatClass from "discourse/ui-kit/helpers/d-concat-class";
import { i18n } from "discourse-i18n";
import SpamWardenStatus from "./spam-warden-status";

export default class SpamWardenRiskScore extends Component {
  get hasScore() {
    return (
      this.args.status === "checked" &&
      this.args.scored &&
      Number.isFinite(this.args.score) &&
      this.args.score >= 0 &&
      this.args.score <= 100
    );
  }

  get riskModifier() {
    if (this.args.exempt) {
      return "--exempt";
    }
    if (!this.hasScore) {
      return "--unknown";
    }
    if (this.args.score >= 70) {
      return "--strong";
    }
    if (this.args.score > 30) {
      return "--moderate";
    }
    return this.args.score > 0 ? "--caution" : "--clear";
  }

  get riskLabel() {
    const labels = {
      "--clear": "no_scored_concern",
      "--caution": "suspicious",
      "--moderate": "moderate_concern",
      "--strong": "high_concern",
    };
    return i18n(`spam_warden.dashboard.${labels[this.riskModifier]}`);
  }

  <template>
    <div
      class={{dConcatClass
        "spam-warden-risk-score"
        this.riskModifier
        (if @compact "--compact")
      }}
      ...attributes
    >
      {{#unless @compact}}<span class="spam-warden-risk-score__label">{{i18n
            "spam_warden.dashboard.risk_score"
          }}</span>{{/unless}}
      {{#if this.hasScore}}
        <strong class="spam-warden-risk-score__value">{{i18n
            "spam_warden.dashboard.percentage"
            value=@score
          }}</strong>
      {{else}}
        <strong class="spam-warden-risk-score__unscored">{{i18n
            (if
              @compact
              "spam_warden.dashboard.na"
              "spam_warden.dashboard.not_scored"
            )
          }}</strong>
      {{/if}}
      {{#if @exempt}}
        <span class="spam-warden-risk-score__override">{{i18n
            "spam_warden.dashboard.exempt"
          }}</span>
        {{#unless @compact}}
          <span class="spam-warden-risk-score__note">{{i18n
              "spam_warden.dashboard.exempt_note"
            }}</span>
        {{/unless}}
      {{else if this.hasScore}}
        <span class="spam-warden-status">{{this.riskLabel}}</span>
      {{else if @compact}}
        <span class="spam-warden-risk-score__label">{{i18n
            "spam_warden.dashboard.not_scored"
          }}</span>
      {{else}}
        <SpamWardenStatus @decision={{@decision}} @status={{@status}} />
      {{/if}}
      {{#unless @compact}}<span class="spam-warden-risk-score__note">{{i18n
            "spam_warden.dashboard.score_note"
          }}</span>{{/unless}}
    </div>
  </template>
}
