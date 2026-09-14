import { withPluginApi } from "discourse/lib/plugin-api";

export default {
  name: "spam-warden-user-list",
  initialize(container) {
    if (!container.lookup("service:current-user")?.admin) {
      return;
    }
    withPluginApi((api) => {
      api.modifyClass("controller:admin-user/index", {
        pluginId: "discourse-spam-warden-open-dashboard",
        queryParams: ["spamGuard"],
        spamGuard: false,
      });
      api.modifyClass(
        "controller:admin-users-list/show",
        (Superclass) =>
          class extends Superclass {
            pluginId = "discourse-spam-warden-user-list-column";

            get columnCount() {
              return super.columnCount + 1;
            }
          }
      );
    });
  },
};
