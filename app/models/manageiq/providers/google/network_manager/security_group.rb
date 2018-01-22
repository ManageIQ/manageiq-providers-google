class ManageIQ::Providers::Google::NetworkManager::SecurityGroup < ::SecurityGroup
  def self.display_name(number = 1)
    n_('Security Group (Google)', 'Security Groups (Google)', number)
  end
end
