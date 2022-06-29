class ManageIQ::Providers::Google::CloudManager::CloudDatabase < ::CloudDatabase
  supports :create
  supports :delete

  def self.params_for_create(ems)
    {
      :fields => [
        {
          :component  => 'text-field',
          :id         => 'name',
          :name       => 'name',
          :label      => _('Cloud Database Name'),
          :isRequired => true,
          :validate   => [{:type => 'required'}],
        },
        {
          :component    => 'select',
          :name         => 'tier',
          :id           => 'tier',
          :label        => _('Tier'),
          :includeEmpty => true,
          :isRequired   => true,
          :validate     => [{:type => 'required'}],
          :options      => ems.cloud_database_flavors.map do |db|
            {
              :label => db[:name],
              :value => db[:name],
            }
          end,
        }
      ],
    }
  end

  def self.raw_create_cloud_database(ext_management_system, options)
    ext_management_system.with_provider_connection(:service => 'sql') do |connection|
      connection.instances.create(:name => options[:name], :tier => options[:tier])
    end
  rescue => err
    _log.error("cloud database=[#{options[:name]}], error: #{err}")
    raise
  end

  def raw_delete_cloud_database
    with_provider_connection(:service => 'sql') do |connection|
      connection.instances.get(name).destroy
    end
  rescue => err
    _log.error("cloud database=[#{name}], error: #{err}")
    raise
  end
end
