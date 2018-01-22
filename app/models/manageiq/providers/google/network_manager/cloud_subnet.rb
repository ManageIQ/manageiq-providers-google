class ManageIQ::Providers::Google::NetworkManager::CloudSubnet < ::CloudSubnet
  def self.display_name(number = 1)
    n_('Cloud Subnet (Google)', 'Cloud Subnets (Google)', number)
  end
end
