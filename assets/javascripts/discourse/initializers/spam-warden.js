import { withPluginApi } from "discourse/lib/plugin-api";

export default {
  name: "spam-warden",
  initialize(container) {
    withPluginApi((api) => {
      api.registerReviewableComponent(
        "ReviewableSpamWarden",
        async () =>
          (await import("../components/reviewable-spam-warden")).default
      );
      if (container.lookup("service:current-user")?.admin) {
        api.addAdminPluginConfigurationNav("discourse-spam-warden", [
          {
            label: "spam_warden.activity",
            route: "adminPlugins.show.spam-warden-activity",
            description: "spam_warden.description",
          },
        ]);
      }
    });
  },
};
