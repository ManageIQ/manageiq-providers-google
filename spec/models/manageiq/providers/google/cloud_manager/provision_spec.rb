describe ManageIQ::Providers::Google::CloudManager::Provision do
  let(:provider) { FactoryGirl.create(:ems_google_with_authentication) }

  context "Cloning" do
    describe "#prepare_for_clone_task" do
      let(:user_data) { "simple test user data" }
      let(:flavor) { FactoryGirl.create(:flavor_google) }
      let(:availability_zone) { FactoryGirl.create(:availability_zone_google) }

      before do
        allow(subject).to receive(:instance_type).and_return(flavor)
        allow(subject).to receive(:dest_availability_zone).and_return(availability_zone)
        allow(subject).to receive(:validate_dest_name)
      end

      it "calls super" do
        # can't test call to super, but we know :validate_dest_name is called in super
        expect(subject).to receive(:validate_dest_name)
        subject.prepare_for_clone_task
      end

      it "handles available user data" do
        expect(subject).to receive(:userdata_payload).and_return(user_data)
        clone_options = subject.prepare_for_clone_task
        expect(clone_options[:metadata]["user-data-encoding"]).to eql("base64")
        expect(clone_options[:metadata]["user-data"]).to eql(Base64.encode64(user_data))
      end

      it "handles absent user data" do
        expect(subject).to receive(:userdata_payload).and_return(nil)
        expect(subject.prepare_for_clone_task[:metadata]).to eql(nil)
      end

      it "sets preemptible flag" do
        subject.options = {:is_preemptible => true}
        clone_options = subject.prepare_for_clone_task

        expect(clone_options).to include(
          :scheduling => {
            :preemptible => true
          }
        )
      end
    end
  end
end
