import { concat } from "@ember/helper";
import getURL from "discourse/lib/get-url";
import SpamWardenEvidence from "./spam-warden-evidence";

export default <template>
  <div class="spam-warden-review" ...attributes>
    <a
      href={{getURL
        (concat
          "/admin/users/"
          @reviewable.spam_warden_user_id
          "/"
          @reviewable.spam_warden_username
          "?spamWarden=true#spam-warden"
        )
      }}
    >
      {{@reviewable.spam_warden_username}}
    </a>
    <SpamWardenEvidence @scan={{@reviewable.spam_warden_scan}} />
  </div>
</template>
