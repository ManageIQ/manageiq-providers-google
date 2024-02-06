class ManageIQ::Providers::Google::CloudManager::Provision < ::MiqProvisionCloud
  include Cloning
  include Disk
  include StateMachine
end
