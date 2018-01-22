class ManageIQ::Providers::Google::NetworkManager::LoadBalancer < ::LoadBalancer
  def self.display_name(number = 1)
    n_('Load Balancer (Google)', 'Load Balancers (Google)', number)
  end
end
