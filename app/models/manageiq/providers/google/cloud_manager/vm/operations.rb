module ManageIQ::Providers::Google::CloudManager::Vm::Operations
  extend ActiveSupport::Concern

  include_concern 'Guest'
  include_concern 'Power'

  included do
    supports :terminate do
      unsupported_reason_add(:terminate, unsupported_reason(:control)) unless supports_control?
    end
  end

  def raw_destroy
    raise "VM has no #{ui_lookup(:table => "ext_management_systems")}, unable to destroy VM" unless ext_management_system
    with_provider_object(&:destroy)
    self.update!(:raw_power_state => "DELETED")
  end
end
