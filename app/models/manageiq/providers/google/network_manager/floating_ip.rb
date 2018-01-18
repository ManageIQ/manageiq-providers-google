class ManageIQ::Providers::Google::NetworkManager::FloatingIp < ::FloatingIp
  def self.display_name(number = 1)
    n_('Floating IP (Google)', 'Floating IPs (Google)', number)
  end
end
