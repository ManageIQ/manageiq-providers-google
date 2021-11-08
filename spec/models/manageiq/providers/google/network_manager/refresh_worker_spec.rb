describe ManageIQ::Providers::Google::NetworkManager::RefreshWorker do
  context "stub" do
    it "won't be seeded" do
      MiqWorkerType.seed
      expect(MiqWorkerType.where(:worker_type => described_class.name).count).to eq 0
    end

    it "allows existing rows of this type to be instantiated" do
      FactoryBot.create(:miq_worker, :type => described_class)
      expect(MiqWorker.first.type).to eq(described_class.name)
    end
  end
end
