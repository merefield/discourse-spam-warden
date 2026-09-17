import Component from "@glimmer/component";
import dConcatClass from "discourse/ui-kit/helpers/d-concat-class";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";

const STATES = {
  allow: { modifier: "--clear", icon: "circle-check" },
  watch: { modifier: "--caution", icon: "eye" },
  review: { modifier: "--caution", icon: "triangle-exclamation" },
  silence: { modifier: "--strong", icon: "circle-exclamation" },
  unknown: { modifier: "--unknown", icon: "circle-question" },
  skipped: { modifier: "--unknown", icon: "circle-question" },
};

export default class SpamWardenStatus extends Component {
  get state() {
    return STATES[this.stateKey];
  }

  get stateKey() {
    if (this.args.status === "skipped") {
      return "skipped";
    }
    return STATES[this.args.decision] ? this.args.decision : "unknown";
  }

  get label() {
    return i18n(`spam_warden.decisions.${this.stateKey}`);
  }

  <template>
    <span
      class={{dConcatClass "spam-warden-status" this.state.modifier}}
      ...attributes
    >
      {{dIcon this.state.icon}}
      {{this.label}}
    </span>
  </template>
}
