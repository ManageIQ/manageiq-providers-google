class ManageIQ::Providers::Google::Inventory::Collector::NetworkManager < ManageIQ::Providers::Google::Inventory::Collector
  def cloud_networks
    connection.networks.all
  end

  def cloud_subnets
    if @subnetworks.nil?
      @subnetworks = connection.subnetworks.all
      # For a backwards compatibility, old GCE networks were created without subnet. It's not possible now, but
      # GCE haven't migrated to new format. We will create a fake subnet for each network without subnets.
      @subnetworks += connection.networks.select { |x| x.ipv4_range.present? }.map do |x|
        Fog::Compute::Google::Subnetwork.new(
          :name               => x.name,
          :gateway_address    => x.gateway_i_pv4,
          :ip_cidr_range      => x.i_pv4_range,
          :id                 => x.id,
          :network            => x.self_link,
          :self_link          => x.self_link,
          :description        => "Subnetwork placeholder for GCE legacy networks without subnetworks",
          :creation_timestamp => x.creation_timestamp,
          :kind               => x.kind
        )
      end
    end

    @subnetworks
  end

  def network_ports
    if @network_ports.nil?
      @network_ports = []
      connection.servers.all.collect do |instance|
        @network_ports += instance.network_interfaces.each do |i|
          i[:device_id] = instance.id
        end
      end
    end

    @network_ports
  end

  def floating_ips(status = :assigned)
    if status == :assigned
      # Fetch assigned floating IPs
      network_ports.flat_map do |network_port|
        network_port[:access_configs].to_a.collect do |access_config|
          {:fixed_ip => network_port[:network_ip], :external_ip => access_config[:nat_ip]}
        end
      end
    else
      # Fetch non assigned static floating IPs
      connection.addresses.reject { |x| x.status == "IN USE" }
    end
  end

  # for IC firewall_rules
  def firewalls
    @firewalls ||= connection.firewalls.all
  end

  # for IC load_balancers
  def forwarding_rules
    connection.forwarding_rules.all
  end

  # for IC load_balancer_pools
  def target_pools
    # Right now we only support network-based load-balancers, instead of the
    # more complicated HTTP/HTTPS load balancers.
    # TODO(jsselman): Add support for http/https proxies
    connection.target_pools.all
  end

  def get_health_check_from_link(link)
    parts = parse_health_check_link(link)
    unless parts
      _log.warn("Unable to parse health check link: #{link}")
      return nil
    end

    return nil unless connection.project == parts[:project]
    get_health_check_cached(parts[:health_check])
  end

  # Lookup a VM in fog via its link to get the VM id (which is equivalent to
  # the ems_ref).
  #
  # @param link [String] the full url to the vm
  # @return [String, nil] the vm id, or nil if it could not be found
  def get_vm_id_from_link(link)
    parts = parse_vm_link(link)
    unless parts
      _log.warn("Unable to parse vm link: #{link}")
      return nil
    end

    # Ensure our connection is using the same project; if it's not we can't
    # do much
    return nil unless connection.project == parts[:project]

    get_vm_id_cached(parts[:zone], parts[:instance])
  end

  private

  # Parses a VM's self_link attribute to extract the project name, zone, and
  # instance name. Used when other services refer to a VM by its link.
  #
  # @param vm_link [String] the full url to the vm (e.g.
  #   "https://www.googleapis.com/compute/v1/projects/myproject/zones/us-central1-a/instances/foobar")
  # @return [Hash{Symbol => String}, nil] a hash containing extracted components
  #   for `:project`, `:zone`, and `:instance`, or nil if the link did not
  #   match.
  def parse_vm_link(vm_link)
    link_regexp = %r{\Ahttps://www\.googleapis\.com/compute/v1/projects/([^/]+)/zones/([^/]+)/instances/([^/]+)\Z}
    m = link_regexp.match(vm_link)
    return nil if m.nil?

    {
      :project  => m[1],
      :zone     => m[2],
      :instance => m[3]
    }
  end

  def parse_health_check_link(health_check_link)
    link_regexp = %r{\Ahttps://www\.googleapis\.com/compute/v1/projects/([^/]+)/global/httpHealthChecks/([^/]+)\Z}

    m = link_regexp.match(health_check_link)
    return nil if m.nil?

    {
      :project      => m[1],
      :health_check => m[2]
    }
  end

  # Look up a VM in fog via a given zone and instance for the current
  # project to get the VM id. Note this method caches matched values during
  # this instance's entire lifetime.
  #
  # @param zone [String] the zone of the vm
  # @param instance [String] the name of the vm
  # @return [String, nil] the vm id, or nil if it could not be found
  def get_vm_id_cached(zone, instance)
    @vm_cache ||= {}

    return @vm_cache.fetch_path(zone, instance) if @vm_cache.has_key_path?(zone, instance)

    begin
      @vm_cache.store_path(zone, instance, connection.get_server(instance, zone).id)
    rescue Fog::Errors::Error, ::Google::Apis::ClientError => _err
      # It is common for load balancers to have "stale" servers defined which fail when queried
      nil
    end
  end

  def get_health_check_cached(health_check)
    @health_check_cache ||= {}

    return @health_check_cache.fetch_path(health_check) if @health_check_cache.has_key_path?(health_check)

    @health_check_cache.store_path(health_check, connection.http_health_checks.get(health_check))
  rescue Fog::Errors::Error, ::Google::Apis::ClientError => _err
    # It is common for load balancers to have "stale" servers defined which fail when queried
    nil
  end
end
