module ManageIQ::Providers
  class Google::NetworkManager::Refresher < ManageIQ::Providers::BaseManager::Refresher
    def post_process_refresh_classes
      []
    end
  end
end
