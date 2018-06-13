class ManageIQ::Providers::Google::CloudManager::Flavor < ::Flavor
  def self.display_name(number = 1)
    n_('Flavor (Google)', 'Flavors (Google)', number)
  end
end
