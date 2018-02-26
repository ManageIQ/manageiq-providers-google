describe ManageIQ::Providers::Google::Regions do
  it "has all the regions" do
    ems = FactoryGirl.create(:ems_google_with_vcr_authentication)

    VCR.use_cassette(described_class.name.underscore) do
      current_regions = described_class.regions.map do |_name, config|
        {:region_name => config[:name], :endpoint => config[:hostname]}
      end
      current_regions.reject! { |r| r[:region_name] == 'example-region' }

      online_regions = ems.connect.client.describe_regions.to_h[:regions]

      # sort for better diff
      current_regions.sort_by! { |r| r[:region_name] }
      online_regions.sort_by! { |r| r[:region_name] }
      expect(online_regions).to eq(current_regions)
    end
  end

  context "disable regions via Settings" do
    it "contains gov_cloud without it being disabled" do
      allow(Settings.ems.ems_google).to receive(:disabled_regions).and_return([])
      expect(described_class.names).to include("example-region")
    end

    it "contains example-region without disabled_regions being set at all - for backwards compatibility" do
      allow(Settings.ems).to receive(:ems_google).and_return(nil)
      expect(described_class.names).to include("example-region")
    end

    it "does not contain some regions that are disabled" do
      allow(Settings.ems.ems_google).to receive(:disabled_regions).and_return(['example-region'])
      expect(described_class.names).not_to include('example-region')
    end
  end

  context "add regions via settings" do
    context "with no additional regions set" do
      let(:settings) do
        {:ems => {:ems_google => {:additional_regions => nil}}}
      end

      it "returns standard regions" do
        stub_settings(settings)
        expect(described_class.names).to eql(described_class::REGIONS.keys)
      end
    end

    context "with one additional" do
      let(:settings) do
        {
          :ems => {
            :ems_google => {
              :additional_regions => {
                :"my-custom-region" => {
                  :name => "My First Custom Region"
                }
              }
            }
          }
        }
      end

      it "returns the custom regions" do
        stub_settings(settings)
        expect(described_class.names).to include("my-custom-region")
      end
    end

    context "with additional regions and disabled regions" do
      let(:settings) do
        {
          :ems => {
            :ems_google => {
              :disabled_regions   => ["my-custom-region-2"],
              :additional_regions => {
                :"my-custom-region-1" => {
                  :name => "My First Custom Region"
                },
                :"my-custom-region-2" => {
                  :name => "My Second Custom Region"
                }
              }
            }
          }
        }
      end

      it "disabled_regions overrides additional_regions" do
        stub_settings(settings)
        expect(described_class.names).to     include("my-custom-region-1")
        expect(described_class.names).not_to include("my-custom-region-2")
      end
    end
  end
end
