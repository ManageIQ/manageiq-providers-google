module ManageIQ::Providers::Google::CloudManager::Vm::Operations
  extend ActiveSupport::Concern
  include Guest
  include Power

  included do
    supports(:terminate) { unsupported_reason(:control) }
  end

  def raw_destroy
    raise "VM has no #{ui_lookup(:table => "ext_management_systems")}, unable to destroy VM" unless ext_management_system
    with_provider_object(&:destroy)
    self.update!(:raw_power_state => "DELETED")
  end
end
