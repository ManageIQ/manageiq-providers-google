module ManageIQ::Providers::Google::Inventory::Persister::Definitions::CloudCollections
  extend ActiveSupport::Concern

  def initialize_cloud_inventory_collections
    %i(availability_zones
       disks
       flavors
       hardwares
       operating_systems
       vms).each do |name|

      add_collection(cloud, name)
    end

    add_miq_templates

    add_key_pairs

    add_cloud_volumes
    add_cloud_volume_snapshots

    add_advanced_settings

    # Custom processing of Ancestry
    %i(vm_and_miq_template_ancestry).each do |name|
      add_collection(cloud, name)
    end
  end

  # ------ IC provider specific definitions -------------------------

  def add_miq_templates
    add_collection(cloud, :miq_templates) do |builder|
      builder.add_properties(
        :model_class => ManageIQ::Providers::Google::CloudManager::Template
      )
    end
  end

  def add_cloud_volumes
    add_collection(cloud, :cloud_volumes) do |builder|
      builder.add_default_values(
        :ems_id => manager.id
      )
    end
  end

  def add_cloud_volume_snapshots
    add_collection(cloud, :cloud_volume_snapshots) do |builder|
      builder.add_default_values(
        :ems_id => manager.id
      )
    end
  end

  def add_key_pairs
    add_collection(cloud, :key_pairs) do |builder|
      builder.add_properties(
        :manager_ref => %i(name fingerprint),
        :model_class => ManageIQ::Providers::Google::CloudManager::AuthKeyPair
      )
    end
  end

  # advanced_settings for VMs
  def add_advanced_settings
    add_collection(cloud, :advanced_settings) do |builder|
      builder.add_properties(
        :manager_ref                  => %i(resource),
        :parent_inventory_collections => %i(vms)
      )
    end
  end
end
