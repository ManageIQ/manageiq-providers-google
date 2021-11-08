class ManageIQ::Providers::Google::NetworkManager::RefreshWorker < ::MiqEmsRefreshWorker
end

# We need a subclass of this refresh worker to avoid it from being a leaf class and seeded as a MiqWorkerType.
class ManageIQ::Providers::Google::NetworkManager::RefreshWorkerBogusChild < ManageIQ::Providers::Google::NetworkManager::RefreshWorker
end
