require 'spec_helper'

describe Vidibus::Resource::Provider::Mongoid do
  let(:subject) do
    ProviderModel.create({
      :name => 'Jenny',
      :uuid => '84e8a690b6e1012e744a6c626d58b44c'
    })
  end
  let(:consumer_client) do
    stub(::Service).discover(consumer.uuid, realm_uuid) { consumer }
    client = Object.new
    stub(consumer).client { client }
    client
  end

  describe 'updating' do
    context 'without registered consumers' do
      it 'should update the record' do
        subject.update_attributes(:name => 'Marta').should be_true
        subject.reload.name.should eq('Marta')
      end
    end

    context 'with registered consumers' do
      before do
        subject.add_resource_consumer(consumer.uuid, realm_uuid)
        subject.add_resource_consumer(another_consumer.uuid, realm_uuid)
      end

      it 'should update the record' do
        subject.update_attributes(:name => 'Marta').should be_true
        subject.reload.name.should eq('Marta')
      end

      it 'should update each service' do
        mock(subject).update_resource_consumer(consumer.uuid, realm_uuid)
        mock(subject).update_resource_consumer(another_consumer.uuid, realm_uuid)
        subject.update_attributes(:name => 'Marta').should be_true
      end

      it 'should not fail without service UUIDs' do
        stub(subject).resource_consumers {[realm_uuid, nil]}
        expect {
          subject.update_attributes(name: 'Marta')
        }.to_not raise_error
      end
    end
  end

  describe 'destroying' do
    context 'without registered consumers' do
      it 'should destroy the record' do
        subject.destroy.should be_true
        expect {subject.reload}.to raise_error
      end
    end

    context 'with registered consumers' do
      before do
        subject.add_resource_consumer(consumer.uuid, realm_uuid)
        subject.add_resource_consumer(another_consumer.uuid, realm_uuid)
      end

      it 'should destroy the record' do
        stub(subject).destroy_resource_consumer
        subject.destroy.should be_true
        expect {subject.reload}.to raise_error
      end

      it 'should remove the resource from all consumer services' do
        mock(subject).destroy_resource_consumer(consumer.uuid, realm_uuid)
        mock(subject).destroy_resource_consumer(another_consumer.uuid, realm_uuid)
        subject.destroy
      end
    end
  end

  describe '#add_resource_consumer' do
    before {stub_services}

    it 'should register a service as consumer' do
      stub(subject).update_resource_consumer(consumer.uuid, realm_uuid)
      subject.add_resource_consumer(consumer.uuid, realm_uuid)
      subject.resource_consumers.should have(1).resource_consumer
    end

    it 'should update the consumer service asynchronously' do
      subject.add_resource_consumer(consumer.uuid, realm_uuid)
      YAML.load(Delayed::Job.first.handler).
        object.should eq('attributes' => subject.attributes)
    end

    it 'should add a job to the resource queue' do
      subject.add_resource_consumer(consumer.uuid, realm_uuid)
      Delayed::Job.first.queue.should eq('resource')
    end

    it 'should send an API request to the consumer service' do
      stub_request(:post, "#{consumer.url}/backend/api/resources/provider_models/#{subject.uuid}").
        with(:body => {:resource => JSON.generate(subject.resourceable_hash), :realm => realm_uuid, :service => this.uuid, :sign => '4977889dcd02e5ae5cd09a1eeb74efe98803cfd8721f4192efda39a31b09e134'}).
          to_return(:status => 200, :body => "", :headers => {})
      subject.add_resource_consumer(consumer.uuid, realm_uuid)
      Delayed::Job.first.invoke_job
    end

    context 'with an existing consumer service' do
      before do
        subject.add_resource_consumer(another_consumer.uuid, realm_uuid)
      end

      it 'should do nothing if consumer has already been added' do
        dont_allow(subject).update_resource_consumer.with_any_args
        subject.add_resource_consumer(another_consumer.uuid, realm_uuid)
      end

      it 'should not update existing consumers' do
        dont_allow(subject).update_resource_consumer(another_consumer.uuid, realm_uuid)
        stub(subject).update_resource_consumer(consumer.uuid, realm_uuid)
        subject.add_resource_consumer(consumer.uuid, realm_uuid)
      end
    end
  end

  describe '#remove_resource_consumer' do
    before do
      stub_services
      stub(subject).create_resource_consumer.with_any_args
      subject.add_resource_consumer(consumer.uuid, realm_uuid)
      stub(consumer_client).delete
    end

    it 'should not delete the consumer service asynchronously' do
      subject.remove_resource_consumer(consumer.uuid, realm_uuid)
      Delayed::Job.count.should eq(0)
    end

    it 'should remove the service with matching uuid and realm' do
      subject.remove_resource_consumer(consumer.uuid, realm_uuid)
      subject.resource_consumers.count.should eq(0)
    end

    it 'should be persistent' do
      subject.remove_resource_consumer(consumer.uuid, realm_uuid)
      subject.reload.resource_consumers.count.should eq(0)
    end

    it 'should not remove other services' do
      subject.add_resource_consumer(another_consumer.uuid, realm_uuid)
      subject.remove_resource_consumer(consumer.uuid, realm_uuid)
      subject.resource_consumers.count.should eq(1)
    end

    it 'should raise an error if no service with given uuid and realm has been added' do
      expect {subject.remove_resource_consumer(consumer.uuid, '289e0df0219f012e52fb6c626d58b44c')}.to raise_error(Vidibus::Resource::Provider::ConsumerNotFoundError)
    end

    it 'should send an API request to the consumer service' do
      path = "/backend/api/resources/provider_models/#{subject.uuid}"
      mock(consumer_client).delete(path, {})
      subject.remove_resource_consumer(consumer.uuid, realm_uuid)
    end
  end

  describe '#refresh_resource_consumer' do
    context 'without resource consumers' do
      it 'should do nothing' do
        dont_allow(subject).update_resource_consumer.with_any_args
        subject.refresh_resource_consumer(consumer.uuid, realm_uuid)
      end
    end

    context 'with a resource consumer' do
      before do
        stub(subject).create_resource_consumer.with_any_args
        subject.add_resource_consumer(consumer.uuid, realm_uuid)
      end

      it 'should send an API request to the consumer service' do
        body = {
          resource: JSON.generate(subject.resourceable_hash),
          realm: realm_uuid,
          service: this.uuid,
          sign: '6a637a923f6b717d8042de916b610a69ad37330e89c054e26a251c107b7e8f44'
        }
        stub_request(:put, "#{consumer.url}/backend/api/resources/provider_models/#{subject.uuid}").
          with(:body => body).
          to_return(:status => 200, :body => '', :headers => {})
        subject.refresh_resource_consumer(consumer.uuid, realm_uuid)
        Delayed::Job.first.invoke_job
      end
    end
  end

  describe '#resourceable_hash' do
    it 'should work without arguments' do
      subject.resourceable_hash.should eq({
        'name' => 'Jenny', 'uuid' => '84e8a690b6e1012e744a6c626d58b44c'
      })
    end

    it 'should work with 2 arguments' do
      subject.resourceable_hash('a', 'b').should eq({
        'name' => 'Jenny', 'uuid' => '84e8a690b6e1012e744a6c626d58b44c'
      })
    end
  end

  describe '.consumers_in_realm' do
    before do
      stub(subject).create_resource_consumer.with_any_args
    end

    it 'should return resources of a given realm' do
      subject.add_resource_consumer(consumer.uuid, realm_uuid)
      ProviderModel.consumers_in_realm(realm_uuid).count.should eq(1)
    end

    it 'should not return resources of other realms' do
      subject.add_resource_consumer(consumer.uuid, '289e0df0219f012e52fb6c626d58b44c')
      ProviderModel.consumers_in_realm(realm_uuid).count.should eq(0)
    end
  end
end
