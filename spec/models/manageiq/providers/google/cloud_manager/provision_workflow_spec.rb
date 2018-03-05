describe ManageIQ::Providers::Google::CloudManager::ProvisionWorkflow do
  include Spec::Support::WorkflowHelper

  let(:admin) { FactoryGirl.create(:user_with_group) }
  let(:ems) { FactoryGirl.create(:ems_google) }
  let(:template) { FactoryGirl.create(:template_google, :name => "template", :ext_management_system => ems) }
  let(:workflow) do
    stub_dialog
    allow(User).to receive_messages(:server_timezone => "UTC")
    described_class.new({:src_vm_id => template.id}, admin.userid)
  end

  context "availability_zone_to_cloud_network" do
    it "has one when it should" do
      FactoryGirl.create(:cloud_network_google, :ext_management_system => ems.network_manager)

      expect(workflow.allowed_cloud_networks.size).to eq(1)
    end

    it "has none when it should" do
      expect(workflow.allowed_cloud_networks.size).to eq(0)
    end
  end
end
