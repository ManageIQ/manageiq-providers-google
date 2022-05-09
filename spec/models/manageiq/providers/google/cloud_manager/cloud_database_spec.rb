describe ManageIQ::Providers::Google::CloudManager::CloudDatabase do
  let(:ems) do
    FactoryBot.create(:ems_google)
  end

  let(:cloud_database) do
    FactoryBot.create(:cloud_database_google, :ext_management_system => ems, :name => "test-db")
  end

  describe 'cloud database actions' do
    let(:connection) do
      double("Fog::Google::SQL::Real")
    end

    let(:instances_client) do
      double("Fog::Google::SQL::Instances")
    end

    let(:instance) do
      double("Fog::Google::SQL::Instance")
    end

    before do
      allow(ems).to receive(:with_provider_connection).and_yield(connection)
      allow(connection).to receive(:instances).and_return(instances_client)
    end

    context '#create_cloud_database' do
      it 'creates the cloud database' do
        expect(instances_client).to receive(:create).with(:name => "test-db", :tier => "db-f1-micro")
        cloud_database.class.raw_create_cloud_database(ems, {:name => "test-db", :tier => "db-f1-micro"})
      end
    end

    context '#delete_cloud_database' do
      it 'deletes the cloud database' do
        allow(instances_client).to receive(:get).with(cloud_database.name).and_return(instance)
        expect(instance).to receive(:destroy)
        cloud_database.delete_cloud_database
      end
    end
  end
end
