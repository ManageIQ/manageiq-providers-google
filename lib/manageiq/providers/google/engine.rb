module ManageIQ
  module Providers
    module Google
      class Engine < ::Rails::Engine
        isolate_namespace ManageIQ::Providers::Google

        config.autoload_paths << root.join('lib').to_s

        def self.vmdb_plugin?
          true
        end

        def self.plugin_name
          _('Google Provider')
        end
      end
    end
  end
end
