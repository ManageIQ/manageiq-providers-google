describe ManageIQ::Providers::Google::CloudManager do
  context ".raw_connect" do
    let(:config) do
      {
        :provider               => "Google",
        :google_project         => "project",
        :google_json_key_string => "encrypted",
        :app_name               => Vmdb::Appliance.PRODUCT_NAME,
        :app_version            => Vmdb::Appliance.VERSION,
        :google_client_options  => { :proxy_url => "proxy_uri" },
      }
    end

    before do
      require 'fog/google'
    end

    it "decrypts json keys" do
      expect(::Fog::Compute).to receive(:new).with(config)

      described_class.raw_connect("project", ManageIQ::Password.encrypt("encrypted"), {:service => "compute"}, "proxy_uri")
    end

    it "works with unencrypted keys" do
      expect(::Fog::Compute).to receive(:new).with(config)

      described_class.raw_connect("project", "encrypted", {:service => "compute"}, "proxy_uri")
    end
  end

  it ".ems_type" do
    expect(described_class.ems_type).to eq('gce')
  end

  it ".description" do
    expect(described_class.description).to eq('Google Compute Engine')
  end

  it "does not create orphaned network_manager" do
    ems = FactoryBot.create(:ems_google)
    same_ems = ExtManagementSystem.find(ems.id)

    ems.destroy
    expect(ExtManagementSystem.count).to eq(0)

    same_ems.save!
    expect(ExtManagementSystem.count).to eq(0)
  end

  it "moves the network_manager to the same zone as the cloud_manager" do
    zone1 = FactoryBot.create(:zone)
    zone2 = FactoryBot.create(:zone)

    ems = FactoryBot.create(:ems_google, :zone => zone1)
    expect(ems.network_manager.zone).to eq zone1
    expect(ems.network_manager.zone_id).to eq zone1.id

    ems.zone = zone2
    ems.save!
    ems.reload

    expect(ems.network_manager.zone).to eq zone2
    expect(ems.network_manager.zone_id).to eq zone2.id
  end

  context "#connectivity" do
    before do
      @google_project = "yourprojectid"
      @google_json_key = "{\r\n\"type\": \"service_account\",\r\n\"private_key_id\": \"abcdefg\"}"
      @e = FactoryBot.create(:ems_google)
      @e.authentications << FactoryBot.create(:authentication, :userid => "_", :auth_key => @google_json_key)
      @e.project = @google_project
    end

    context "#connect " do
      it "defaults" do
        expect(described_class).to receive(:raw_connect) do |project, auth_key|
          expect(project).to eq(@google_project)
          expect(auth_key).to eq(@google_json_key)
        end
        @e.connect
      end

      it "sends proxy uri when set to fog-google" do
        Settings.http_proxy.gce = {
          :host     => "192.168.24.99",
          :port     => "1234",
          :user     => "my_user",
          :password => "my_password"
        }

        require 'fog/google'
        expect(Fog::Compute::Google).to receive(:new) do |options|
          expect(options.fetch_path(:google_client_options, :proxy_url).to_s)
            .to eq("http://my_user:my_password@192.168.24.99:1234")
        end
        @e.connect
      end
    end

    context "#validation" do
      it "handles incorrect password" do
        allow(ManageIQ::Providers::Google::CloudManager).to receive(:connect).and_raise(StandardError)
        expect { @e.verify_credentials }.to raise_error(MiqException::MiqInvalidCredentialsError, /Invalid Google JSON*/)
      end
    end
  end

  context 'catalog types' do
    let(:ems) { FactoryBot.create(:ems_google) }

    it "#supported_google_types" do
      expect(ems.supported_catalog_types).to eq(%w(google))
    end
  end
end
