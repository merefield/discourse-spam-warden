import { i18n } from "discourse-i18n";
import SpamWardenUserSummary from "../../components/spam-warden-user-summary";

export default <template>
  {{#if @outletArgs.user.spam_warden_summary}}
    <div class="directory-table__cell spam-warden-column">
      <span class="directory-table__label">{{i18n "spam_warden.title"}}</span>
      <SpamWardenUserSummary @user={{@outletArgs.user}} />
    </div>
  {{/if}}
</template>
