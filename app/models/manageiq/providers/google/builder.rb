class ManageIQ::Providers::Google::Builder
  class << self
    def build_inventory(ems, target)
      manager_type = ManageIQ::Providers::Inflector.manager_type(target)

      manager_type = 'Cloud' unless %w(Cloud Network).include?(manager_type)

      collector_class = "ManageIQ::Providers::Google::Inventory::Collector::#{manager_type}Manager".safe_constantize
      persister_class = "ManageIQ::Providers::Google::Inventory::Persister::#{manager_type}Manager".safe_constantize
      parser_class    = "ManageIQ::Providers::Google::Inventory::Parser::#{manager_type}Manager".safe_constantize

      inventory(ems, target, collector_class, persister_class, [parser_class])
    end

    private

    def inventory(manager, raw_target, collector_class, persister_class, parsers_classes)
      collector = collector_class.new(manager, raw_target)
      persister = persister_class.new(manager, raw_target)

      ::ManageIQ::Providers::Google::Inventory.new(
        persister,
        collector,
        parsers_classes.map(&:new)
      )
    end
  end
end
