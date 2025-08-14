module ManageIQ
  module Providers
    module Google
      class Engine < ::Rails::Engine
        isolate_namespace ManageIQ::Providers::Google

        config.autoload_paths << root.join('lib')

        def self.vmdb_plugin?
          true
        end

        def self.plugin_name
          _('Google Provider')
        end

        def self.init_loggers
          $gce_log ||= Vmdb::Loggers.create_logger("gce.log")
        end

        def self.apply_logger_config(config)
          Vmdb::Loggers.apply_config_value(config, $gce_log, :level_gce)
        end
      end
    end
  end
end
