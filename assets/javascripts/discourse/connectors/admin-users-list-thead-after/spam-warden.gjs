import Component from "@glimmer/component";
import { service } from "@ember/service";
import { i18n } from "discourse-i18n";

export default class SpamWardenColumnHeader extends Component {
  @service currentUser;

  <template>
    {{#if this.currentUser.admin}}
      <div
        class="directory-table__column-header spam-warden-column-header"
      >{{i18n "spam_warden.title"}}</div>
    {{/if}}
  </template>
}
