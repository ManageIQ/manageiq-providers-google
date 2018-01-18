class ManageIQ::Providers::Google::NetworkManager::NetworkPort < ::NetworkPort
  def self.display_name(number = 1)
    n_('Network Port (Google)', 'Network Ports (Google)', number)
  end
end
