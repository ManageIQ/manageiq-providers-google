class ManageIQ::Providers::Google::Inventory::Persister::ContainerManager < ManageIQ::Providers::Kubernetes::Inventory::Persister::ContainerManager
  require_nested :WatchNotice
end
