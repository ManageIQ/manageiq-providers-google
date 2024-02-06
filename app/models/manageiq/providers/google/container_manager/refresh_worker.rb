class ManageIQ::Providers::Google::ContainerManager::RefreshWorker < ManageIQ::Providers::BaseManager::RefreshWorker
  def self.settings_name
    :ems_refresh_worker_google_gke
  end
end
