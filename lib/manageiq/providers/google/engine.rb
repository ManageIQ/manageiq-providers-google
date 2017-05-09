module ManageIQ
  module Providers
    module Google
      class Engine < ::Rails::Engine
        isolate_namespace ManageIQ::Providers::Google
      end
    end
  end
end
