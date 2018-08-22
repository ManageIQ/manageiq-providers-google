class ManageIQ::Providers::Google::Inventory::Persister::CloudManager < ManageIQ::Providers::Google::Inventory::Persister
  include ManageIQ::Providers::Google::Inventory::Persister::Definitions::CloudCollections

  def initialize_inventory_collections
    initialize_cloud_inventory_collections
  end
end
