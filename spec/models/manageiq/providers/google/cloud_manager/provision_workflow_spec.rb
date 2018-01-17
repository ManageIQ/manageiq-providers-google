describe ManageIQ::Providers::Google::CloudManager::ProvisionWorkflow do
  include Spec::Support::WorkflowHelper

  let(:admin) { FactoryGirl.create(:user_with_group) }
  let(:provider) do
    allow(User).to receive_messages(:server_timezone => "UTC")
    FactoryGirl.create(:ems_google)
  end

  let(:ems) { FactoryGirl.create(:ems_google) }
  let(:template) { FactoryGirl.create(:template_google, :name => "template", :ext_management_system => ems) }
  let(:workflow) do
    stub_dialog
    allow(User).to receive_messages(:server_timezone => "UTC")
    wf = described_class.new({:src_vm_id => template.id}, admin.userid)
    wf
  end

  context "with empty relationships" do
    it "#allowed_cloud_networks" do
      expect(workflow.allowed_cloud_networks).to eq({})
    end
  end

  context "with valid relationships" do
    it "#allowed_cloud_networks" do
      cn = FactoryGirl.create(:cloud_network)
      ems.cloud_networks << cn
      expect(workflow.allowed_cloud_networks).to eq(cn.id => cn.name)
    end
  end

  context "cloud networks" do
    before do
      @az1 = FactoryGirl.create(:availability_zone, :ext_management_system => ems)
      FactoryGirl.create(:cloud_network_google, :ext_management_system => ems.network_manager)
    end

    context "#allowed_cloud_networks" do
      it "without an Availability Zone" do
        expect(workflow.allowed_cloud_networks.length).to eq(1)
      end

      it "with an Availability Zone" do
        workflow.values[:placement_availability_zone] = [@az1.id, @az1.name]

        expect(workflow.allowed_cloud_networks.length).to eq(1)
      end
    end
  end
end
