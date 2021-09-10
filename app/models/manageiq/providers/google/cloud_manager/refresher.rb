module ManageIQ::Providers::Google
  class CloudManager::Refresher < ManageIQ::Providers::BaseManager::Refresher
    def post_process_refresh_classes
      [::Vm]
    end
  end
end
