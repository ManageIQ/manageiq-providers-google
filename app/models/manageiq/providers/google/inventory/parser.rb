class ManageIQ::Providers::Google::Inventory::Parser < ManagerRefresh::Inventory::Parser
  require_nested :CloudManager
  require_nested :NetworkManager

  VENDOR_GOOGLE = "google".freeze
end
