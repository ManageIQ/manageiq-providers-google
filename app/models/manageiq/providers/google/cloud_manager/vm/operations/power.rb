module ManageIQ::Providers::Google::CloudManager::Vm::Operations::Power
  extend ActiveSupport::Concern
  included do
    supports_not :suspend
  end

  def validate_pause
    validate_unsupported(_("Pause Operation"))
  end

  def raw_suspend
    validate_unsupported(_("Suspend Operation"))
  end

  def raw_pause
    validate_unsupported(_("Pause Operation"))
  end

  def raw_start
    with_provider_object(&:start)
    self.update!(:raw_power_state => "starting")
  end

  def raw_stop
    with_provider_object(&:stop)
    self.update!(:raw_power_state => "stopping")
  end
end
