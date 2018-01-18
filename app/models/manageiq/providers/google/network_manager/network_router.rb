class ManageIQ::Providers::Google::NetworkManager::NetworkRouter < ::NetworkRouter
  def self.display_name(number = 1)
    n_('Network Router (Google)', 'Network Routers (Google)', number)
  end
end
