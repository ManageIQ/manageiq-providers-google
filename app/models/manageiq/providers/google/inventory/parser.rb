class ManageIQ::Providers::Google::Inventory::Parser < ManageIQ::Providers::Inventory::Parser
  require_nested :CloudManager
  require_nested :NetworkManager

  VENDOR_GOOGLE = "google".freeze
end
