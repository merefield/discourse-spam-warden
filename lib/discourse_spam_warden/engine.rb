# frozen_string_literal: true

module DiscourseSpamWarden
  class Engine < ::Rails::Engine
    engine_name PLUGIN_NAME
    isolate_namespace DiscourseSpamWarden
    config.autoload_paths << File.expand_path("..", __dir__)
  end
end
