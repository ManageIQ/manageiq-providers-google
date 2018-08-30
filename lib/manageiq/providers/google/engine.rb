module ManageIQ
  module Providers
    module Google
      class Engine < ::Rails::Engine
        isolate_namespace ManageIQ::Providers::Google

        def self.plugin_name
          _('Google Provider')
        end
      end
    end
  end
end
