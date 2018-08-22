class ManageIQ::Providers::Google::Inventory < ManagerRefresh::Inventory
  require_nested :Collector
  require_nested :Parser
  require_nested :Persister
end
