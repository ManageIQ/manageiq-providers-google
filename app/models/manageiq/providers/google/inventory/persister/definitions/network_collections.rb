module ManageIQ::Providers::Google::Inventory::Persister::Definitions::NetworkCollections
  extend ActiveSupport::Concern

  def initialize_network_inventory_collections
    %i(cloud_networks
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
       security_groups).each do |name|

      add_collection(network, name)
    end

    add_cloud_subnet_network_ports

    add_firewall_rules

    add_load_balancer_listener_pools
  end

  # ------ IC provider specific definitions -------------------------

  def add_cloud_subnet_network_ports
    add_collection(network, :cloud_subnet_network_ports) do |builder|
      builder.add_properties(:manager_ref_allowed_nil => %i(cloud_subnet))
    end
  end

  def add_firewall_rules
    add_collection(network, :firewall_rules) do |builder|
      builder.add_properties(:manager_ref_allowed_nil => %i(source_security_group))
    end
  end

  def add_load_balancer_listener_pools
    add_collection(network, :load_balancer_listener_pools) do |builder|
      builder.add_properties(:manager_ref_allowed_nil => %i(load_balancer_pool))
    end
  end
end
