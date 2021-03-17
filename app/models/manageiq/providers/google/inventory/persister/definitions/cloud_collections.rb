module ManageIQ::Providers::Google::Inventory::Persister::Definitions::CloudCollections
  extend ActiveSupport::Concern

  def initialize_cloud_inventory_collections
    %i[
      availability_zones
      cloud_volumes
      disks
      flavors
      hardwares
      operating_systems
      miq_templates
      vms
    ].each do |name|
      add_cloud_collection(name)
    end

    add_auth_key_pairs

    add_cloud_volume_snapshots

    add_advanced_settings

    # Custom processing of Ancestry
    %i(vm_and_miq_template_ancestry).each do |name|
      add_collection(cloud, name)
    end
  end

  # ------ IC provider specific definitions -------------------------

  def add_cloud_volume_snapshots
    add_cloud_collection(:cloud_volume_snapshots)
  end

  def add_auth_key_pairs
    add_cloud_collection(:auth_key_pairs) do |builder|
      builder.add_properties(
        :manager_ref => %i(name fingerprint),
      )
    end
  end

  # advanced_settings for VMs
  def add_advanced_settings
    add_cloud_collection(:vms_and_templates_advanced_settings) do |builder|
      builder.add_properties(
        :manager_ref                  => %i(resource),
        :model_class                  => ::AdvancedSetting,
        :parent_inventory_collections => %i(vms)
      )
    end
  end
end
