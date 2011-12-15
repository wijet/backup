# encoding: utf-8

require File.expand_path('../../spec_helper.rb', __FILE__)

describe 'Storage::SCP',
    :if => Backup::SpecLive::CONFIG['storage']['scp']['specs_enabled'] do
  let(:trigger) { 'archive_scp' }

  def remote_files_for(storage, trigger)
    remote_path = File.join(storage.path, trigger, storage.time)

    files = []
    storage.transferred_files do |local_file, remote_file|
      files << File.join(remote_path, remote_file)
    end
    files
  end

  def check_remote_for(storage, files)
    if (storage.username == Backup::USER) && (storage.ip == 'localhost')
      files.each do |file|
        if !File.exist?(file)
          return false
        end
      end
      true
    else
      errors = []
      storage.send(:connection) do |ssh|
        files.each do |file|
          ssh.exec!("ls '#{file}'") do |ch, stream, data|
            errors << data if stream == :stderr
          end
        end
      end
      errors.empty?
    end
  end

  def clean_remote!(storage)
    return if (storage.username == Backup::USER) && (storage.ip == 'localhost') &&
        (storage.path == Backup::SpecLive::TMP_PATH)
    storage.send(:connection) do |ssh|
      ssh.exec!("rm -r '#{storage.path}'")
    end
  end

  it 'should store the archive on the remote' do
    model = h_set_trigger(trigger)
    # grab it, since it will be "cleaned" during cycling
    storage = model.storages.first.dup

    model.perform!

    remote_files = remote_files_for(storage, trigger)
    remote_files.count.should == 1

    check_remote_for(storage, remote_files).should be_true

    clean_remote!(storage)
  end

  describe 'Storage::SCP Cycling' do
    context 'when archives exceed `keep` setting' do
      it 'should remove the oldest archive' do
        archives = []

        model = h_set_trigger(trigger)
        storage = model.storages.first.dup
        model.perform!
        remote_files = remote_files_for(storage, trigger)
        remote_files.count.should == 1
        archives += remote_files
        sleep 1

        model = h_set_trigger(trigger)
        storage = model.storages.first.dup
        model.perform!
        remote_files = remote_files_for(storage, trigger)
        remote_files.count.should == 1
        archives += remote_files
        sleep 1

        model = h_set_trigger(trigger)
        storage = model.storages.first.dup
        model.perform!
        remote_files = remote_files_for(storage, trigger)
        remote_files.count.should == 1
        archives += remote_files

        check_remote_for(storage, archives[1..2]).should be_true
        check_remote_for(storage, [archives[0]]).should be_false

        clean_remote!(storage)
      end
    end

    context 'when an archive to be removed does not exist' do
      it 'should log a warning and continue' do
        archives = []

        model = h_set_trigger(trigger)
        storage = model.storages.first.dup
        model.perform!
        remote_files = remote_files_for(storage, trigger)
        remote_files.count.should == 1
        archives += remote_files
        sleep 1

        model = h_set_trigger(trigger)
        storage = model.storages.first.dup
        model.perform!
        remote_files = remote_files_for(storage, trigger)
        remote_files.count.should == 1
        archives += remote_files

        check_remote_for(storage, archives[0..1]).should be_true
        # remove archive directory cycle! will attempt to remove
        dir = archives[0].split('/')[0...-1].join('/')
        if (storage.username == Backup::USER) && (storage.ip == 'localhost')
          FileUtils.rm_r(dir)
        else
          storage.send(:connection) do |ssh|
            ssh.exec!("rm -r '#{dir}'")
          end
        end

        check_remote_for(storage, [archives[0]]).should be_false
        check_remote_for(storage, [archives[1]]).should be_true

        model = h_set_trigger(trigger)
        storage = model.storages.first.dup
        expect do
          model.perform!
        end.not_to raise_error

        Backup::Logger.has_warnings?.should be_true

        remote_files = remote_files_for(storage, trigger)
        remote_files.count.should == 1
        archives += remote_files

        check_remote_for(storage, archives[1..2]).should be_true

        clean_remote!(storage)
      end
    end

  end # describe 'Storage::SCP Cycling'

end
