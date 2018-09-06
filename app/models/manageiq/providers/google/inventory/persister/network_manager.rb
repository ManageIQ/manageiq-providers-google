class ManageIQ::Providers::Google::Inventory::Persister::NetworkManager < ManageIQ::Providers::Google::Inventory::Persister
  include ManageIQ::Providers::Google::Inventory::Persister::Definitions::NetworkCollections

  def initialize_inventory_collections
    initialize_network_inventory_collections

    initialize_cloud_inventory_collections
  end

  def initialize_cloud_inventory_collections
    %i(vms).each do |name|
      add_collection(cloud, name) do |builder|
        builder.add_properties(
          :parent   => manager.parent_manager,
          :strategy => :local_db_cache_all
        )
      end
    end
  end
end
