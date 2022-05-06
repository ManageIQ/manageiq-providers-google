class ManageIQ::Providers::Google::CloudManager::CloudVolume < ::CloudVolume
  def self.params_for_create(_)
    {
      :fields => []
    }
  end

  def params_for_attach
    {
      :fields => [
        {
          :component => 'text-field',
          :name      => 'device_mountpoint',
          :id        => 'device_mountpoint',
          :label     => _('Device Mountpoint')
        }
      ]
    }
  end
end
