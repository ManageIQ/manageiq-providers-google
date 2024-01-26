class ManageIQ::Providers::Google::Inventory::Persister < ManageIQ::Providers::Inventory::Persister
  def initialize_inventory_collections
    initialize_cloud_inventory_collections
    initialize_network_inventory_collections
  end

  def initialize_cloud_inventory_collections
    %i[
      availability_zones
      cloud_databases
      cloud_database_flavors
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

  def initialize_network_inventory_collections
    %i[
      cloud_networks
      cloud_subnets
      floating_ips
      load_balancers
      load_balancer_health_checks
      load_balancer_health_check_members
      load_balancer_listeners
      load_balancer_pools
      load_balancer_pool_members
      load_balancer_pool_member_pools
      network_ports
      security_groups
    ].each do |name|
      add_network_collection(name)
    end

    add_cloud_subnet_network_ports

    add_firewall_rules

    add_load_balancer_listener_pools
  end

  # ------ IC provider specific definitions -------------------------

  def add_cloud_subnet_network_ports
    add_network_collection(:cloud_subnet_network_ports) do |builder|
      builder.add_properties(:manager_ref_allowed_nil => %i(cloud_subnet))
    end
  end

  def add_firewall_rules
    add_network_collection(:firewall_rules) do |builder|
      builder.add_properties(
        :manager_ref             => %i(name resource source_security_group direction host_protocol port end_port source_ip_range),
        :manager_ref_allowed_nil => %i(source_security_group)
      )
    end
  end

  def add_load_balancer_listener_pools
    add_network_collection(:load_balancer_listener_pools) do |builder|
      builder.add_properties(:manager_ref_allowed_nil => %i(load_balancer_pool))
    end
  end
end
