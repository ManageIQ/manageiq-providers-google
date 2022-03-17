class ManageIQ::Providers::Google::CloudManager::EventCatcher < ManageIQ::Providers::BaseManager::EventCatcher
  require_nested :Runner

  def self.all_valid_ems_in_zone
    # Only valid to start an EventCatcher if the Pub/Sub service is enabled
    # on the project
    super.select { |ems| ems.supports?(:events) }
  end
end
