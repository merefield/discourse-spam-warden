import Component from "@glimmer/component";
import { concat } from "@ember/helper";
import { service } from "@ember/service";
import getURL from "discourse/lib/get-url";
import { i18n } from "discourse-i18n";
import SpamWardenEvidence from "../../components/spam-warden-evidence";

export default class SpamWardenAiReview extends Component {
  @service currentUser;

  get visible() {
    return (
      this.args.outletArgs.model.spam_warden_scan ||
      (this.currentUser?.admin &&
        this.args.outletArgs.model.spam_warden_ai_account_id)
    );
  }

  <template>
    {{#if this.visible}}
      <div class="spam-warden-ai-review" ...attributes>
        {{#if @outletArgs.model.spam_warden_scan}}
          <SpamWardenEvidence @scan={{@outletArgs.model.spam_warden_scan}} />
        {{/if}}
        {{#if this.currentUser.admin}}
          {{#if @outletArgs.model.spam_warden_ai_account_id}}
            <a
              href={{getURL
                (concat
                  "/admin/users/"
                  @outletArgs.model.spam_warden_ai_account_id
                  "#spam-warden"
                )
              }}
            >{{i18n "spam_warden.ai.account"}}</a>
          {{/if}}
        {{/if}}
      </div>
    {{/if}}
  </template>
}
