class ManageIQ::Providers::Google::Builder < ManageIQ::Providers::Inventory::Builder
  class << self
    def allowed_manager_types
      %w(Cloud Network)
    end

    def default_manager_type
      'Cloud'
    end
  end
end
