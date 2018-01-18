class ManageIQ::Providers::Google::NetworkManager::CloudNetwork < ::CloudNetwork
  def self.display_name(number = 1)
    n_('Cloud Network (Google)', 'Cloud Networks (Google)', number)
  end
end
