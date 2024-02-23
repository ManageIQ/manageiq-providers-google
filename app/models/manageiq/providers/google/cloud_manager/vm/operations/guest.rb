module ManageIQ::Providers::Google::CloudManager::Vm::Operations::Guest
  extend ActiveSupport::Concern

  included do
    supports :reboot_guest do
      if current_state == "on"
        unsupported_reason(:control)
      else
        _("The VM is not powered on")
      end
    end
  end

  def raw_reboot_guest
    with_provider_object(&:reboot)
    self.update!(:raw_power_state => "reboot") # show state as suspended
  end
end
