class ManageIQ::Providers::Google::Inventory::Parser::CloudManager < ManageIQ::Providers::Google::Inventory::Parser
  def initialize
    super

    @cloud_volume_url_to_source_image_id = {}
    @cloud_volume_url_to_id = {}
  end

  def parse
    log_header = "MIQ(#{self.class.name}.#{__method__}) Collecting data for EMS name: [#{collector.manager.name}] id: [#{collector.manager.id}]"
    _log.info("#{log_header}...")

    availability_zones
    flavors
    key_pairs
    cloud_volumes
    cloud_volume_snapshots
    images
    instances

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
      :cpus        => flavor.guest_cpus,
      :description => flavor.description,
      :ems_ref     => flavor.name,
      :enabled     => !flavor.deprecated,
      :memory      => flavor.memory_mb * 1.megabyte,
      :name        => flavor.name
    )
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
    collector.images.each do |image|
      persister_miq_template = image(image)

      image_os(persister_miq_template, image)
    end
  end

  def image(image)
    uid = image.id.to_s

    persister.miq_templates.build(
      :deprecated         => image.kind == "compute#image" ? !image.deprecated.nil? : false,
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
  def key_pairs
    project_key_pairs.each do |ssh_key|
      persister.key_pairs.build(
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
      key_pair = persister.key_pairs.build(
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
      :cpu_total_cores => series[:cpus],
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
end
