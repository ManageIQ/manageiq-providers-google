class ManageIQ::Providers::Google::Inventory::Parser < ManageIQ::Providers::Inventory::Parser
  require_nested :CloudManager
  require_nested :ContainerManager
  require_nested :NetworkManager

  VENDOR_GOOGLE = "google".freeze
  GCP_HEALTH_STATUS_MAP = {
    "HEALTHY"   => "InService",
    "UNHEALTHY" => "OutOfService"
  }.freeze

  def initialize
    super

    @cloud_volume_url_to_source_image_id = {}
    @cloud_volume_url_to_id = {}

    # Simple mapping from target pool's self_link url to the created
    # target pool entity.
    @target_pool_index = {}

    # Another simple mapping from target pool's self_link url to the set of
    # lbs that point at it
    @target_pool_link_to_load_balancers = {}

    # Cache of images in use by active instances
    @active_images = Set.new
  end

  def parse
    log_header = "MIQ(#{self.class.name}.#{__method__}) Collecting data for EMS name: [#{collector.manager.name}] id: [#{collector.manager.id}]"
    _log.info("#{log_header}...")

    availability_zones
    flavors
    auth_key_pairs
    cloud_databases
    cloud_database_flavors
    cloud_volumes
    cloud_volume_snapshots
    instances
    images

    cloud_networks
    network_ports
    floating_ips

    load_balancers
    load_balancer_pools
    forwarding_rules

    _log.info("#{log_header}...Complete")
  end

  private

  def availability_zones
    collector.availability_zones.each do |az|
      persister.availability_zones.build(
        :ems_ref => az.name,
        :name    => az.name
      )
    end
  end

  def flavors
    collector.flavors.each do |flavor|
      flavor(flavor)
    end
  end

  def flavor_by_uid_and_zone_uid(flavor_uid, availability_zone_uid)
    flavor = collector.flavor(flavor_uid, availability_zone_uid)
    flavor(flavor)
  end

  def flavor(flavor)
    persister.flavors.build(
      :cpu_total_cores => flavor.guest_cpus,
      :description     => flavor.description,
      :ems_ref         => flavor.name,
      :enabled         => !flavor.deprecated,
      :memory          => flavor.memory_mb * 1.megabyte,
      :name            => flavor.name
    )
  end

  def cloud_databases
    collector.cloud_databases.each do |cloud_database|
      persister.cloud_databases.build(
        :ems_ref               => cloud_database.name,
        :name                  => cloud_database.name,
        :status                => cloud_database.state,
        :db_engine             => cloud_database.database_version,
        :cloud_database_flavor => persister.cloud_database_flavors.lazy_find(cloud_database.tier)
      )
    end
  end

  def cloud_database_flavors
    collector.cloud_database_flavors.each do |cloud_database_flavor|
      persister.cloud_database_flavors.build(
        :ems_ref => cloud_database_flavor.tier,
        :name    => cloud_database_flavor.tier,
        :enabled => true,
        :memory  => cloud_database_flavor.ram
      )
    end
  end

  def cloud_volumes
    collector.cloud_volumes.each do |cloud_volume|
      zone_id = parse_uid_from_url(cloud_volume.zone)

      persister.cloud_volumes.build(
        :availability_zone => persister.availability_zones.lazy_find(zone_id),
        :base_snapshot     => persister.cloud_volume_snapshots.lazy_find(cloud_volume.source_snapshot),
        :creation_time     => cloud_volume.creation_timestamp,
        :description       => cloud_volume.description,
        :ems_ref           => cloud_volume.id.to_s,
        :name              => cloud_volume.name,
        :size              => cloud_volume.size_gb.to_i.gigabyte,
        :status            => cloud_volume.status,
        :volume_type       => parse_uid_from_url(cloud_volume.type)
      )

      # Take note of the source_image_id so we can expose it in parse_instance
      @cloud_volume_url_to_source_image_id[cloud_volume.self_link] = cloud_volume.source_image_id
      @cloud_volume_url_to_id[cloud_volume.self_link] = cloud_volume.id.to_s
    end
  end

  def cloud_volume_snapshots
    collector.cloud_volume_snapshots.each do |snapshot|
      persister.cloud_volume_snapshots.build(
        :creation_time => snapshot.creation_timestamp,
        :description   => snapshot.description,
        :ems_ref       => snapshot.id.to_s,
        :name          => snapshot.name,
        :size          => snapshot.disk_size_gb.to_i.gigabytes,
        :status        => snapshot.status,
        :cloud_volume  => persister.cloud_volumes.lazy_find(snapshot.source_disk)
      )

      persister_miq_template = image(snapshot)

      image_os(persister_miq_template, snapshot)
    end
  end

  def images
    collector.images.reject(&method(:skip_image?)).each do |image|
      persister_miq_template = image(image)

      image_os(persister_miq_template, image)
    end
  end

  def image(image)
    uid = image.id.to_s

    persister.miq_templates.build(
      :deprecated         => deprecated_image?(image),
      :ems_ref            => uid,
      :location           => image.self_link,
      :name               => image.name || uid,
      :publicly_available => true,
      :connection_state   => "connected",
      :raw_power_state    => "never",
      :template           => true,
      :uid_ems            => uid,
      :vendor             => VENDOR_GOOGLE
    )
  end

  def instances
    collector.instances.each do |instance|
      uid = instance.id.to_s

      flavor_uid = parse_uid_from_url(instance.machine_type)
      zone_uid = parse_uid_from_url(instance.zone)

      # TODO(mslemr) lazy_find (now result needed immediately)
      flavor = persister.flavors.find(flavor_uid)

      # If the flavor isn't found in our index, check if it is a custom flavor
      # that we have to get directly
      flavor = flavor_by_uid_and_zone_uid(flavor_uid, zone_uid) if flavor.nil?

      parent_image_uid = parse_instance_parent_image(instance)
      @active_images << parent_image_uid if parent_image_uid

      persister_vm = persister.vms.build(
        :availability_zone => persister.availability_zones.lazy_find(zone_uid),
        :description       => instance.description,
        :ems_ref           => uid,
        :flavor            => flavor,
        :location          => "unknown", # TODO(mslemr) instance.self_link?,
        :name              => instance.name || uid,
        :genealogy_parent  => persister.miq_templates.lazy_find(parent_image_uid),
        :connection_state  => "connected",
        :raw_power_state   => instance.status,
        :uid_ems           => uid,
        :vendor            => VENDOR_GOOGLE,
      )

      instance_os(persister_vm, parent_image_uid)
      instance_hardware(persister_vm, instance, flavor)
      instance_key_pairs(persister_vm, instance)
      instance_advanced_settings(persister_vm, instance)
    end
  end

  # Adding global key-pairs (needed when instances count == 0)
  def auth_key_pairs
    project_key_pairs.each do |ssh_key|
      persister.auth_key_pairs.build(
        :name        => ssh_key[:name],
        :fingerprint => ssh_key[:fingerprint]
      )
    end
  end

  # @param persister_vm [InventoryObject<ManageIQ::Providers::Google::CloudManager::Vm>]
  # @param instance [Fog::Compute::Google::Server]
  def instance_key_pairs(persister_vm, instance)
    # Add project common ssh-keys with keys specific to this instance
    instance_ssh_keys = project_key_pairs | parse_compute_metadata_ssh_keys(instance.metadata)

    instance_ssh_keys.each do |ssh_key|
      key_pair = persister.auth_key_pairs.build(
        :name        => ssh_key[:name],       # manager_ref
        :fingerprint => ssh_key[:fingerprint] # manager_ref
      )

      key_pair.vms ||= []
      key_pair.vms << persister_vm
    end
  end

  # @param persister_vm [InventoryObject<ManageIQ::Providers::Google::CloudManager::Vm>]
  # @param series [InventoryObject<ManageIQ::Providers::Google::CloudManager::Flavor>]
  def instance_hardware(persister_vm, instance, series)
    persister_hardware = persister.hardwares.build(
      :vm_or_template  => persister_vm, # manager_ref
      :cpu_total_cores => series[:cpu_total_cores],
      :memory_mb       => series[:memory] / 1.megabyte
    )

    hardware_disks(persister_hardware, instance)
  end

  # @param persister_vm [InventoryObject<ManageIQ::Providers::Google::CloudManager::Vm>]
  # @param instance [Fog::Compute::Google::Server]
  def instance_advanced_settings(persister_vm, instance)
    persister.vms_and_templates_advanced_settings.build(
      :resource     => persister_vm, # manager_ref
      :name         => "preemptible?",
      :display_name => N_("Is VM Preemptible"),
      :description  => N_("Whether or not the VM is 'preemptible'. See"\
                               " https://cloud.google.com/compute/docs/instances/preemptible for more details."),
      :value        => instance.scheduling[:preemptible].to_s,
      :read_only    => true
    )
  end

  # @param persister_template [InventoryObject<ManageIQ::Providers::Google::CloudManager::Template]
  # @param image [Fog::Compute::Google::Snapshot, Fog::Compute::Google::Image]
  def image_os(persister_template, image)
    persister.operating_systems.build(
      :vm_or_template => persister_template, # manager_ref
      :product_name   => get_os_product_name(image)
    )
  end

  # Operating system for Vm (i.e. instance)
  # It's name is taken from parent image's OS
  # Note: Not added when parent image not found
  #
  # @param persister_vm [InventoryObject<ManageIQ::Providers::Google::CloudManager::Vm>]
  # @param parent_image_uid [String] UID of vm's template
  def instance_os(persister_vm, parent_image_uid)
    persister.operating_systems.build(
      :vm_or_template => persister_vm,
      :product_name   => persister.operating_systems.lazy_find(
        persister.miq_templates.lazy_find(parent_image_uid),
        :key => :product_name
      )
    )
  end

  # @param persister_hardware [InventoryObject<Hardware>]
  # @param instance [Fog::Compute::Google::Server]
  def hardware_disks(persister_hardware, instance)
    instance.disks.each do |attached_disk|
      cloud_volume_ems_ref = @cloud_volume_url_to_id[attached_disk[:source]]
      persister_cloud_volume = persister.cloud_volumes.find(cloud_volume_ems_ref)
      next if persister_cloud_volume.nil?

      persister.disks.build(
        :backing         => persister_cloud_volume,
        :backing_type    => 'CloudVolume',
        :controller_type => VENDOR_GOOGLE,
        :device_name     => attached_disk[:device_name], # manager_ref
        :device_type     => "disk",
        :hardware        => persister_hardware,          # manager_ref
        :location        => attached_disk[:index],
        :size            => persister_cloud_volume.size
      )
    end
  end

  # ---

  def get_os_product_name(storage)
    if storage.kind == 'compute#image'
      OperatingSystem.normalize_os_name(storage.name)
    else
      'unknown'
    end
  end

  # Get image's (miq_template's) ems_ref from
  # instance disks (connected to cloud_volume's `self_link`)
  def parse_instance_parent_image(instance)
    parent_image_uid = nil

    instance.disks.each do |disk|
      parent_image_uid = @cloud_volume_url_to_source_image_id[disk[:source]]
      next if parent_image_uid.nil?
      break
    end

    parent_image_uid
  end

  # @param ssh_key [Hash]
  def key_pairs_ems_ref(ssh_key)
    "#{ssh_key[:name]}:#{ssh_key[:fingerprint]}"
  end

  # Ssh keys that are common to all instances in the project
  def project_key_pairs
    if @project_key_pairs.nil?
      project_common_metadata = collector.project_instance_metadata
      @project_key_pairs      = parse_compute_metadata_ssh_keys(project_common_metadata)
    end
    @project_key_pairs
  end

  def parse_compute_metadata(metadata, key)
    metadata_item = metadata[:items].to_a.detect { |x| x[:key] == key }
    metadata_item.to_h[:value]
  end

  def parse_compute_metadata_ssh_keys(metadata)
    require 'sshkey'

    ssh_keys = []

    # Find the sshKeys property in the instance metadata
    metadata_ssh_keys = parse_compute_metadata(metadata, "sshKeys")

    metadata_ssh_keys.to_s.split("\n").reject(&:blank?).each do |ssh_key|
      # Google returns the key in the form username:public_key
      name, public_key = ssh_key.split(":", 2)
      next if public_key.blank?

      begin
        fingerprint = SSHKey.sha1_fingerprint(public_key)

        ssh_keys << {
          :name        => name,
          :public_key  => public_key,
          :fingerprint => fingerprint
        }
      rescue => err
        _log.warn("Failed to parse public key #{name}: #{err}")
      end
    end

    ssh_keys
  end

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
        vm_id = collector.instances_by_self_link[member_link]&.id

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

  def parse_uid_from_url(url)
    # A lot of attributes in gce are full URLs with the
    # uid being the last component.  This helper method
    # returns the last component of the url
    url.split('/')[-1]
  end

  def deprecated_image?(image)
    image.kind == "compute#image" ? !image.deprecated.nil? : false
  end

  def skip_image?(image)
    return false if options.get_deprecated_images
    return false unless deprecated_image?(image)
    return false if @active_images.include?(image.id.to_s)

    true
  end
end
