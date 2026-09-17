export default {
  resource: "admin.adminPlugins.show",
  path: "/plugins",
  map() {
    this.route("spam-warden-activity", { path: "activity" });
  },
};
