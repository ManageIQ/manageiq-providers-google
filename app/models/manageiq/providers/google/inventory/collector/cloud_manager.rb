class ManageIQ::Providers::Google::Inventory::Collector::CloudManager < ManageIQ::Providers::Google::Inventory::Collector
  attr_reader :project_key_pairs

  def availability_zones
    connection.zones.all
  end

  def flavors
    flavors_by_zone = connection.list_aggregated_machine_types.items
    flavors_by_zone.values.flat_map(&:machine_types).compact.uniq(&:id)
  end

  def flavor(flavor_uid, availability_zone_uid)
    connection.get_machine_type(flavor_uid, availability_zone_uid)
  end

  def cloud_volumes
    connection.disks.all
  end

  # !also parse vms! there
  def cloud_volume_snapshots
    connection.snapshots.all
  end

  def images
    connection.images.all
  end

  def instances
    connection.servers.all
  end

  # Used for ssh keys common to all instances in the project
  def project_instance_metadata
    if @common_instance_metadata.nil?
      @common_instance_metadata = connection.projects.get(manager.project).common_instance_metadata
    end
    @common_instance_metadata
  end
end
