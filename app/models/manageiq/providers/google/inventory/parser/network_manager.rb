class ManageIQ::Providers::Google::Inventory::Parser::NetworkManager < ManageIQ::Providers::Google::Inventory::Parser
  GCP_HEALTH_STATUS_MAP = {
    "HEALTHY"   => "InService",
    "UNHEALTHY" => "OutOfService"
  }.freeze

  def initialize
    super

    # Simple mapping from target pool's self_link url to the created
    # target pool entity.
    @target_pool_index = {}

    # Another simple mapping from target pool's self_link url to the set of
    # lbs that point at it
    @target_pool_link_to_load_balancers = {}
  end

  def parse
    log_header = "MIQ(#{self.class.name}.#{__method__}) Collecting data for EMS name: [#{collector.manager.name}] id: [#{collector.manager.id}]"
    _log.info("#{log_header}...")

    cloud_networks
    network_ports
    floating_ips

    load_balancers
    load_balancer_pools
    forwarding_rules

    _log.info("#{log_header}...Complete")
  end

  private

  def cloud_networks
    collector.cloud_networks.each do |network|
      persister_cloud_network = persister.cloud_networks.build(
        :cidr    => network.ipv4_range,
        :ems_ref => network.id.to_s, # manager_ref
        :enabled => true,
        :name    => network.name,
        :status  => "active"
      )

      cloud_subnets(persister_cloud_network, network)
      security_group(persister_cloud_network)
    end
  end

  # @param persister_cloud_network [InventoryObject<ManageIQ::Providers::Google::NetworkManager::CloudNetwork>]
  # @param network [Fog::Compute::Google::Network]
  def cloud_subnets(persister_cloud_network, network)
    @subnets_by_network_link ||= collector.cloud_subnets.each_with_object({}) { |x, subnets| (subnets[x.network] ||= []) << x }
    @subnets_by_network_link[network.self_link]&.each do |cloud_subnet|
      uid = cloud_subnet.id.to_s
      persister.cloud_subnets.build(
        :cidr          => cloud_subnet.ip_cidr_range,
        :cloud_network => persister_cloud_network,
        :ems_ref       => uid, # manager_ref
        :gateway       => cloud_subnet.gateway_address,
        :name          => cloud_subnet.name || uid,
        :status        => "active",
      )
    end
  end

  def network_ports
    collector.network_ports.each do |network_port|
      uid = network_port[:network_ip]

      persister_network_port = persister.network_ports.build(
        :device      => persister.vms.lazy_find(network_port[:device_id]),
        :device_ref  => network_port[:device_id].to_s,
        :ems_ref     => uid,
        :mac_address => nil,
        :name        => network_port[:name],
        :status      => nil,
      )

      persister_network_port.security_groups ||= []
      persister_network_port.security_groups << persister.security_groups.lazy_find(parse_uid_from_url(network_port[:network]))

      cloud_subnet_network_port(persister_network_port, network_port)
    end
  end

  # @param persister_network_port [InventoryObject<ManageIQ::Providers::Google::MetworkManager::NetworkPort>]
  # @param network_port [Hash]
  def cloud_subnet_network_port(persister_network_port, network_port)
    subnets_by_link ||= collector.cloud_subnets.each_with_object({}) { |x, subnets| subnets[x.self_link] = x }

    # For legacy GCE networks without subnets, we also try a network link
    cloud_subnet = subnets_by_link[network_port[:subnetwork]] || subnets_by_link[network_port[:network]]

    persister.cloud_subnet_network_ports.build(
      :cloud_subnet => persister.cloud_subnets.lazy_find(cloud_subnet.id.to_s),
      :network_port => persister_network_port,
      :address      => network_port[:network_ip]
    )
  end

  def floating_ips
    collector.floating_ips(:non_assigned).each do |ip|
      persister.floating_ips.build(
        :address          => ip.address,
        :ems_ref          => ip.address,
        :fixed_ip_address => nil,
        :network_port     => nil,
        :vm               => nil
      )
    end
    collector.floating_ips(:assigned).each do |ip|
      network_port = persister.network_ports.lazy_find(ip[:fixed_ip])
      vm = persister.network_ports.lazy_find(ip[:fixed_ip], :key => :device)

      persister.floating_ips.build(
        :address          => ip[:external_ip],
        :ems_ref          => ip[:external_ip],
        :fixed_ip_address => ip[:fixed_ip],
        :network_port     => network_port,
        :vm               => vm
      )
    end
  end

  # @param persister_cloud_network [InventoryObject<ManageIQ::Providers::Google::NetworkManager::CloudNetwork>]
  def security_group(persister_cloud_network)
    uid = persister_cloud_network.name
    persister_security_group = persister.security_groups.build(
      :cloud_network => persister_cloud_network,
      :ems_ref       => uid,
      :name          => uid
    )

    network_firewalls = collector.firewalls.select do |firewall|
      parse_uid_from_url(firewall.network) == persister_cloud_network.name
    end

    firewall_rules(persister_security_group, network_firewalls)
  end

  # @param persister_security_group [InventoryObject<ManageIQ::Providers::Google::NetworkManager::SecurityGroup>]
  # @param firewalls [Array<Fog::Compute::Google::Firewall>]
  def firewall_rules(persister_security_group, firewalls)
    firewalls.each do |firewall|
      name = firewall.name
      source_ip_range = firewall.source_ranges.nil? ? "0.0.0.0/0" : firewall.source_ranges.first

      firewall.allowed.each do |fw_allowed|
        protocol      = fw_allowed[:ip_protocol].upcase
        allowed_ports = fw_allowed[:ports].to_a.first

        if allowed_ports.nil?
          # The ICMP protocol doesn't have ports so set to -1
          from_port = to_port = -1
        else
          from_port, to_port = allowed_ports.split("-", 2)
        end

        persister.firewall_rules.build(
          :direction             => "inbound",
          :end_port              => to_port,
          :host_protocol         => protocol,
          :name                  => name,
          :port                  => from_port,
          :resource              => persister_security_group,
          :source_ip_range       => source_ip_range,
          :source_security_group => nil
        )
      end
    end
  end

  def load_balancers
    forwarding_rules = collector.forwarding_rules

    forwarding_rules.each do |forwarding_rule|
      persister_load_balancer = persister.load_balancers.build(
        :ems_ref => forwarding_rule.id.to_s,
        :name    => forwarding_rule.name
      )

      if forwarding_rule.target
        # Make sure we link the target link back to this instance for future
        # back-references
        @target_pool_link_to_load_balancers[forwarding_rule.target] ||= Set.new
        @target_pool_link_to_load_balancers[forwarding_rule.target].add(persister_load_balancer)
      end
    end
  end

  def forwarding_rules
    collector.forwarding_rules.each do |forwarding_rule|
      load_balancer_listener(forwarding_rule)
    end
  end

  # @param forwarding_rule [Fog::Compute::Google::ForwardingRule]
  def load_balancer_listener(forwarding_rule)
    # Only TCP/UDP/SCTP forwarding rules have ports
    has_ports = %w(TCP UDP SCTP).include?(forwarding_rule.ip_protocol)
    port_range = (parse_port_range(forwarding_rule.port_range) if has_ports)

    persister_lb_listener = persister.load_balancer_listeners.build(
      :name                     => forwarding_rule.name,
      :ems_ref                  => forwarding_rule.id.to_s,
      :load_balancer_protocol   => forwarding_rule.ip_protocol,
      :instance_protocol        => forwarding_rule.ip_protocol,
      :load_balancer_port_range => port_range,
      :instance_port_range      => port_range,
      :load_balancer            => persister.load_balancers.lazy_find(forwarding_rule.id.to_s)
    )

    load_balancer_listener_pool(persister_lb_listener, forwarding_rule)
  end

  # @param persister_lb_listener [InventoryObject<ManageIQ::Providers::google::NetworkManager::LoadBalancerListener]
  # @param forwarding_rule [Fog::Compute::Google::ForwardingRule]
  def load_balancer_listener_pool(persister_lb_listener, forwarding_rule)
    persister_lb_listener_pool = persister.load_balancer_listener_pools.build(
      :load_balancer_listener => persister_lb_listener,
      :load_balancer_pool     => @target_pool_index[forwarding_rule.target]
    )

    persister_lb_listener.load_balancer_listener_pools ||= []
    persister_lb_listener.load_balancer_listener_pools << persister_lb_listener_pool
  end

  def load_balancer_pools
    collector.target_pools.each do |target_pool|
      persister_lb_pool = persister.load_balancer_pools.build(
        :ems_ref => target_pool.id.to_s,
        :name    => target_pool.name
      )

      @target_pool_index[target_pool.self_link] = persister_lb_pool

      load_balancer_pool_members(persister_lb_pool, target_pool)
      load_balancer_health_check(target_pool)
    end
  end

  # @param persister_lb_pool [InventoryObject<ManageIQ::Providers::Google::NetworkManager::LoadBalancerPool>]
  # @param target_pool [Fog::Compute::Google::TargetPool]
  def load_balancer_pool_members(persister_lb_pool, target_pool)
    target_pool.instances.to_a.each do |member_link|
      persister_lb_pool_member = persister.load_balancer_pool_members.find(Digest::MD5.base64digest(member_link))

      if persister_lb_pool_member.nil?
        vm_id = collector.get_vm_id_from_link(member_link)

        persister_lb_pool_member = persister.load_balancer_pool_members.build(
          :ems_ref => Digest::MD5.base64digest(member_link),
          :vm      => (persister.vms.lazy_find(vm_id) if vm_id)
        )
      end
      persister.load_balancer_pool_member_pools.build(
        :load_balancer_pool        => persister_lb_pool,
        :load_balancer_pool_member => persister_lb_pool_member
      )
    end
  end

  # @param target_pool [Fog::Compute::Google::TargetPool]
  def load_balancer_health_check(target_pool)
    # Target pools aren't required to have health checks
    return if target_pool.health_checks.blank?

    # For some reason a target pool has a list of health checks, but the API
    # won't accept more than one. Ignore the rest
    if target_pool.health_checks.size > 1
      _log.warn("Expected one health check on target pool but found many! Ignoring all but the first.")
    end

    health_check = collector.get_health_check_from_link(target_pool.health_checks.first)
    load_balancers = @target_pool_link_to_load_balancers[target_pool.self_link]
    return if load_balancers.blank?

    load_balancers.each do |persister_load_balancer|
      # load_balancer and listener have same ems_ref
      load_balancer_listener = persister.load_balancer_listeners.lazy_find(persister_load_balancer.ems_ref)

      # TODO(mslemr) this return is in old refresh
      # return nil if load_balancer_listener.nil? #TODO: return inside collect?

      uid = "#{persister_load_balancer.ems_ref}_#{target_pool.id}_#{health_check.id}"
      persister_lb_health_check = persister.load_balancer_health_checks.build(
        :ems_ref                => uid,
        :healthy_threshold      => health_check.healthy_threshold,
        :interval               => health_check.check_interval_sec,
        :load_balancer          => persister_load_balancer,
        :load_balancer_listener => load_balancer_listener,
        :name                   => health_check.name,
        :protocol               => "HTTP",
        :port                   => health_check.port,
        :timeout                => health_check.timeout_sec,
        :unhealthy_threshold    => health_check.unhealthy_threshold,
        :url_path               => health_check.request_path,
      )

      load_balancer_health_check_members(persister_lb_health_check, target_pool)
    end
  end

  # @param persister_lb_health_check [InventoryObject<ManageIQ::Providers::Google::NetworkManager::LoadBalancerHealthCheck>]
  # @param target_pool [Fog::Compute::Google::TargetPool]
  def load_balancer_health_check_members(persister_lb_health_check, target_pool)
    return if target_pool.instances.blank?
    # First attempt to get the health of the instance
    # Due to a bug in fog, there's no way to get the health of an individual
    # member. Instead we have to get the health of the entire target_pool,
    # which if it fails means we skip.
    # Issue here: https://github.com/fog/fog-google/issues/162
    target_pool.get_health.collect do |instance_link, instance_health|
      # attempt to look up the load balancer member
      member = persister.load_balancer_pool_members.find(Digest::MD5.base64digest(instance_link))
      return nil unless member

      # Lookup our health state in the health status map; default to
      # "OutOfService" if we can't find a mapping.
      status = "OutOfService"
      unless instance_health.nil?
        gcp_status = instance_health[0][:health_state]

        if GCP_HEALTH_STATUS_MAP.include?(gcp_status)
          status = GCP_HEALTH_STATUS_MAP[gcp_status]
        else
          _log.warn("Unable to find an explicit health status mapping for state: #{gcp_status} - defaulting to 'OutOfService'")
        end
      end

      persister.load_balancer_health_check_members.build(
        :load_balancer_health_check => persister_lb_health_check,
        :load_balancer_pool_member  => member,
        :status                     => status,
        :status_reason              => ""
      )
    end
  rescue Fog::Errors::Error, Google::Apis::ClientError => err
    # It is common for load balancers to have "stale" servers defined which fail when queried
    _log.warn("Unexpected error when probing health for target pool #{target_pool.name}: #{err}") unless err.message.start_with?("notFound: ")
    return []
  end
  #
  # --- helpers ---
  #

  # Parses a port range returned by GCP from a string to a Range. Note that
  # GCP treats the empty port range "" to mean all ports; hence this method
  # returns 0..65535 when the input is the empty string.
  #
  # @param port_range [String] the port range (e.g. "" or "80-123" or "11")
  # @return [Range] a range representing the port range
  def parse_port_range(port_range)
    # Three forms:
    # "80"
    # "5000-5010"
    # "" (all ports)
    m = /\A(\d+)(?:-(\d+))?\Z/.match(port_range)
    return 0..65_535 unless m

    start = Integer(m[1])
    finish = m[2] ? Integer(m[2]) : start
    start..finish
  end
end
