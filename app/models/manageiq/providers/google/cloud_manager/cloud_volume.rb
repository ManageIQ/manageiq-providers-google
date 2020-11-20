class ManageIQ::Providers::Google::CloudManager::CloudVolume < ::CloudVolume
  def self.params_for_create(_)
    {
      :fields => []
    }
  end
end
