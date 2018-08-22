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

  def key_pairs(instances)
    ssh_keys = []

    # Find all key pairs added directly to GCE instances
    instances.each do |instance|
      ssh_keys |= parse_compute_metadata_ssh_keys(instance.metadata)
    end

    # Add ssh keys that are common to all instances in the project
    project_common_metadata = connection.projects.get(manager.project).common_instance_metadata
    @project_key_pairs      = parse_compute_metadata_ssh_keys(project_common_metadata)

    ssh_keys |= @project_key_pairs
    ssh_keys
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

    metadata_ssh_keys.to_s.split("\n").each do |ssh_key|
      # Google returns the key in the form username:public_key
      name, public_key = ssh_key.split(":", 2)
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
