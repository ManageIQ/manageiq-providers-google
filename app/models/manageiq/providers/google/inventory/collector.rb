class ManageIQ::Providers::Google::Inventory::Collector < ManageIQ::Providers::Inventory::Collector
  def initialize(_manager, _target)
    super
  end

  def compute
    @compute ||= manager.connect(:service => "compute")
  end

  def sql
    @sql ||= manager.connect(:service => "sql")
  end

  attr_reader :project_key_pairs

  def availability_zones
    compute.zones.all
  end

  def cloud_databases
    @cloud_databases ||= sql.instances.all
  rescue Google::Apis::ClientError # Catch an API exception if the sqladmin API isn't enabled
    []
  end

  def cloud_database_flavors
    @cloud_database_flavors ||= sql.tiers.all
  rescue Google::Apis::ClientError # Catch an API exception if the sqladmin API isn't enabled
    []
  end

  def flavors
    compute.machine_types.all
  end

  def flavor(flavor_uid, availability_zone_uid)
    compute.get_machine_type(flavor_uid, availability_zone_uid)
  end

  def cloud_volumes
    compute.disks.all
  end

  # !also parse vms! there
  def cloud_volume_snapshots
    compute.snapshots.all
  end

  def images
    compute.images.all
  end

  def instances
    @instances ||= compute.servers.all
  end

  def instances_by_self_link
    @instances_by_self_link ||= instances.index_by(&:self_link)
  end

  # Used for ssh keys common to all instances in the project
  def project_instance_metadata
    if @common_instance_metadata.nil?
      @common_instance_metadata = compute.projects.get(manager.project).common_instance_metadata
    end
    @common_instance_metadata
  end

  def cloud_networks
    compute.networks.all
  end

  def cloud_subnets
    if @subnetworks.nil?
      @subnetworks = compute.subnetworks.all
      # For a backwards compatibility, old GCE networks were created without subnet. It's not possible now, but
      # GCE haven't migrated to new format. We will create a fake subnet for each network without subnets.
      @subnetworks += compute.networks.select { |x| x.ipv4_range.present? }.map do |x|
        Fog::Google::Compute::Subnetwork.new(
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
      compute.servers.all.collect do |instance|
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
      compute.addresses.reject { |x| x.status == "IN USE" }
    end
  end

  # for IC firewall_rules
  def firewalls
    @firewalls ||= compute.firewalls.all
  end

  # for IC load_balancers
  def forwarding_rules
    compute.forwarding_rules.all
  end

  # for IC load_balancer_pools
  def target_pools
    # Right now we only support network-based load-balancers, instead of the
    # more complicated HTTP/HTTPS load balancers.
    # TODO(jsselman): Add support for http/https proxies
    compute.target_pools.all
  end

  def get_health_check_from_link(link)
    parts = parse_health_check_link(link)
    unless parts
      _log.warn("Unable to parse health check link: #{link}")
      return nil
    end

    return nil unless compute.project == parts[:project]

    get_health_check_cached(parts[:health_check])
  end

  private

  def parse_health_check_link(health_check_link)
    link_regexp = %r{\Ahttps://www\.googleapis\.com/compute/v1/projects/([^/]+)/global/httpHealthChecks/([^/]+)\Z}

    m = link_regexp.match(health_check_link)
    return nil if m.nil?

    {
      :project      => m[1],
      :health_check => m[2]
    }
  end

  def get_health_check_cached(health_check)
    @health_check_cache ||= {}

    return @health_check_cache.fetch_path(health_check) if @health_check_cache.has_key_path?(health_check)

    check = get_health_check(health_check)
    @health_check_cache.store_path(health_check, check) if check
    check
  end

  def get_health_check(health_check)
    compute.http_health_checks.get(health_check)
  rescue Fog::Errors::Error, ::Google::Apis::ClientError => err
    # It is common for load balancers to have "stale" servers defined which fail when queried
    _log.warn("#{log_header} failed to query for health check: #{err}") unless err.message.start_with?("notFound: ")
    nil
  end

  def log_header
    "EMS [#{manager&.name}] id: [#{manager&.id}]"
  end
end
