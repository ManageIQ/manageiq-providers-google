class ManageIQ::Providers::Google::Inventory::Parser::CloudManager < ManageIQ::Providers::Google::Inventory::Parser
  include ManageIQ::Providers::Google::RefreshHelperMethods

  def initialize
    super
    # Mapping from disk url to source image id.
    @disk_to_source_image_id = {}
    # Mapping from disk url to disk uid
    @disk_to_id = {}

    @project_key_pairs = Set.new
  end

  def parse
    log_header = "MIQ(#{self.class.name}.#{__method__}) Collecting data for EMS name: [#{collector.manager.name}] id: [#{collector.manager.id}]"
    _log.info("#{log_header}...")

    # binding.pry
    availability_zones
    flavors
    cloud_volumes
    cloud_volume_snapshots

    images do |image, inventory_object|
      image_os(inventory_object, image)
    end
    instances

    _log.info("#{log_header}...Complete")
  end

  private

  def availability_zones
    collector.availability_zones.each do |az|
      persister.availability_zones.find_or_build(az.name).assign_attributes(
        :name => az.name
      )
    end
  end

  def flavors
    collector.flavors.each do |flavor|
      instance_flavor(flavor)
    end
  end

  def get_flavor(flavor_uid, availability_zone_uid)
    flavor = collector.flavor(flavor_uid, availability_zone_uid)
    instance_flavor(flavor)
  end

  def instance_flavor(flavor)
    persister.flavors.find_or_build(flavor.name).assign_attributes(
      :name        => flavor.name,
      :description => flavor.description,
      :enabled     => !flavor.deprecated,
      :cpus        => flavor.guest_cpus,
      :memory      => flavor.memory_mb * 1.megabyte
    )
  end

  # TODO: where is cloud_tenant assoc?
  def cloud_volumes
    collector.cloud_volumes.each do |cloud_volume|
      zone_id = parse_uid_from_url(cloud_volume.zone)

      persister.cloud_volumes.find_or_build(cloud_volume.id.to_s).assign_attributes(
        :availability_zone => persister.availability_zones.lazy_find(zone_id),
        :base_snapshot     => persister.cloud_volume_snapshots.lazy_find(cloud_volume.source_snapshot),
        :creation_time     => cloud_volume.creation_timestamp,
        :description       => cloud_volume.description,
        :name              => cloud_volume.name,
        :size              => cloud_volume.size_gb.to_i.gigabyte,
        :status            => cloud_volume.status,
        :volume_type       => parse_uid_from_url(cloud_volume.type)
      )

      # Take note of the source_image_id so we can expose it in parse_instance
      @disk_to_source_image_id[cloud_volume.self_link] = cloud_volume.source_image_id
      @disk_to_id[cloud_volume.self_link] = cloud_volume.id.to_s
    end
  end

  def cloud_volume_snapshots
    collector.cloud_volume_snapshots.each do |snapshot|
      persister.cloud_volume_snapshots.find_or_build(snapshot.id.to_s).assign_attributes(
        :creation_time => snapshot.creation_timestamp,
        :description   => snapshot.description,
        :name          => snapshot.name,
        :size          => snapshot.disk_size_gb.to_i.gigabytes,
        :status        => snapshot.status,
        :cloud_volume  => persister.cloud_volumes.lazy_find(snapshot.source_disk)
      )

      image = snapshot
      uid = image.id.to_s

      # TODO: duplicite code
      persister_miq_template = persister.miq_templates.find_or_build(uid).assign_attributes(
        :deprecated         => image.kind == "compute#image" ? !image.deprecated.nil? : false,
        :location           => image.self_link,
        :name               => image.name || uid,
        :publicly_available => true,
        :raw_power_state    => "never",
        :template           => true,
        :uid_ems            => uid,
        :vendor             => VENDOR_GOOGLE
      )
      image_os(persister_miq_template, image)
    end
  end

  def images
    collector.images.each do |image|
      uid = image.id.to_s

      persister_image = persister.miq_templates.find_or_build(uid).assign_attributes(
        :deprecated         => image.kind == "compute#image" ? !image.deprecated.nil? : false,
        :location           => image.self_link,
        :name               => image.name || uid,
        :publicly_available => true,
        :raw_power_state    => "never",
        :template           => true,
        :uid_ems            => uid,
        :vendor             => VENDOR_GOOGLE
      )
      yield image, persister_image
    end
  end

  def instances
    instances = collector.instances

    key_pairs(instances) # TODO: merge with loop below

    instances.each do |instance|
      uid = instance.id.to_s

      flavor_uid = parse_uid_from_url(instance.machine_type)
      zone_uid = parse_uid_from_url(instance.zone)

      flavor = persister.flavors.find(flavor_uid)

      # If the flavor isn't found in our index, check if it is a custom flavor
      # that we have to get directly
      flavor = get_flavor(flavor_uid, zone_uid) if flavor.nil?

      availability_zone = persister.availability_zones.lazy_find(zone_uid)
      parent_image_uid = parse_instance_parent_image(instance)

      persister_instance = persister.vms.find_or_build(uid).assign_attributes(
        :availability_zone => availability_zone,
        :description       => instance.description,
        :flavor            => flavor,
        :location          => "unknown", # TODO: ??? || "unknown"
        :name              => instance.name || uid,
        :genealogy_parent  => persister.miq_templates.lazy_find(parent_image_uid),
        :raw_power_state   => instance.status,
        :uid_ems           => uid,
        :vendor            => VENDOR_GOOGLE,
      )

      instance_os(persister_instance, parent_image_uid)
      instance_hardware(persister_instance, instance, flavor)
      instance_key_pairs(persister_instance, instance)
      instance_advanced_settings(persister_instance, instance)
      #
    end
  end

  def key_pairs(instances)
    collector.key_pairs(instances).each do |ssh_key|
      persister.key_pairs.build(
        :name        => ssh_key[:name],
        :fingerprint => ssh_key[:fingerprint]
      )
    end
  end

  # TODO: collector.parse - refactoring needed
  def instance_key_pairs(persister_instance, instance)
    # Add project common ssh-keys with keys specific to this instance
    instance_ssh_keys = collector.parse_compute_metadata_ssh_keys(instance.metadata) | collector.project_key_pairs
    instance_ssh_keys.each do |ssh_key|
      # select existing key pairs
      # existing_key_pairs = persister.key_pairs.data.select do |kp|
      #   kp.name == ssh_key[:name] && kp.fingerprint == ssh_key[:fingerprint]
      # end

      key_pair = persister.key_pairs.find(:name        => ssh_key[:name],
                                          :fingerprint => ssh_key[:fingerprint])
      if key_pair.nil?
        key_pair = persister.key_pairs.build(
          :name        => ssh_key[:name],       # manager_ref
          :fingerprint => ssh_key[:fingerprint] # manager_ref
        )
      end

      key_pair.vms ||= []
      key_pair.vms << persister_instance
    end
  end

  def instance_hardware(persister_instance, instance, series)
    persister_hardware = persister.hardwares.build(
      :vm_or_template  => persister_instance, # manager_ref
      :cpu_total_cores => series[:cpus],
      :memory_mb       => series[:memory] / 1.megabyte
    )
    hardware_disks(persister_hardware, instance)
  end

  def instance_advanced_settings(persister_instance, instance)
    persister.advanced_settings.build(
      :resource     => persister_instance, # manager_ref
      :name         => "preemptible?",
      :display_name => N_("Is VM Preemptible"),
      :description  => N_("Whether or not the VM is 'preemptible'. See"\
                               " https://cloud.google.com/compute/docs/instances/preemptible for more details."),
      :value        => instance.scheduling[:preemptible].to_s,
      :read_only    => true
    )
  end

  # @param persister_template [InventoryObject]
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
  # @param persister_vm [InventoryObject] -> IC <ManageIQ::Providers::Google::CloudManager::Vm>
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

  def hardware_disks(persister_hardware, instance)
    instance.disks.each do |attached_disk|
      # TODO(mslemr): can't be better solution?
      cloud_volume_ems_ref = @disk_to_id[attached_disk[:source]]
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
      parent_image_uid = @disk_to_source_image_id[disk[:source]]
      next if parent_image_uid.nil?
      break
    end

    parent_image_uid
  end

  # @param ssh_key [Hash]
  def key_pairs_ems_ref(ssh_key)
    "#{ssh_key[:name]}:#{ssh_key[:fingerprint]}"
  end
end
