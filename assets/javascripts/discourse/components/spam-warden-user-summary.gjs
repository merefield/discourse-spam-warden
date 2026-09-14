import { concat } from "@ember/helper";
import getURL from "discourse/lib/get-url";
import { i18n } from "discourse-i18n";
import SpamWardenRiskScore from "./spam-warden-risk-score";

export default <template>
  {{#if @user.spam_warden_summary}}
    <div class="spam-warden-user-summary" ...attributes>
      <a
        class="spam-warden-user-summary__link"
        href={{getURL
          (concat
            "/admin/users/"
            @user.id
            "/"
            @user.username
            "?spamWarden=true#spam-warden"
          )
        }}
      >
        <span class="sr-only">{{i18n
            "spam_warden.open_user_dashboard"
            username=@user.username
          }}</span>
        <SpamWardenRiskScore
          @compact={{true}}
          @exempt={{@user.spam_warden_summary.exempt}}
          @score={{@user.spam_warden_summary.scan.score}}
          @scored={{@user.spam_warden_summary.scan.scored}}
          @decision={{@user.spam_warden_summary.scan.decision}}
          @status={{@user.spam_warden_summary.scan.status}}
        />
      </a>
    </div>
  {{/if}}
</template>
