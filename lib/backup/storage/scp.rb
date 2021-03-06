# encoding: utf-8

##
# Only load the Net::SSH and Net::SCP library/gems
# when the Backup::Storage::SCP class is loaded
Backup::Dependency.load('net-ssh')
Backup::Dependency.load('net-scp')


module Backup
  module Storage
    class SCP < Base

      ##
      # Server credentials
      attr_accessor :username, :password

      ##
      # Server IP Address and SCP port
      attr_accessor :ip, :port

      ##
      # Path to store backups to
      attr_accessor :path

      ##
      # This is the remote path to where the backup files will be stored
      def remote_path
        File.join(path, TRIGGER, @time)
      end

      ##
      # Performs the backup transfer
      def perform!
        super
        transfer!
        cycle!
      end

    private

      ##
      # Set configuration defaults before evaluating configuration block,
      # after setting defaults from Storage::Base
      def pre_configure
        super
        @port ||= 22
        @path ||= 'backups'
      end

      ##
      # Adjust configuration after evaluating configuration block,
      # after adjustments from Storage::Base
      def post_configure
        super
        @path = path.sub(/^\~\//, '')
      end

      ##
      # Establishes a connection to the remote server
      # and yields the Net::SSH connection.
      # Net::SCP will use this connection to transfer backups
      def connection
        Net::SSH.start(
          ip, username, :password => password, :port => port
        ) {|ssh| yield ssh }
      end

      ##
      # Transfers the archived file to the specified remote server
      def transfer!
        connection do |ssh|
          create_remote_directories(ssh)

          files_to_transfer do |local_file, remote_file|
            Logger.message "#{storage_name} started transferring " +
                "'#{local_file}' to '#{ip}'."

            ssh.scp.upload!(
              File.join(local_path, local_file),
              File.join(remote_path, remote_file)
            )
          end
        end
      end

      ##
      # Removes the transferred archive file from the server
      def remove!
        messages = []
        transferred_files do |local_file, remote_file|
          messages << "#{storage_name} started removing '#{local_file}' from '#{ip}'."
        end
        Logger.message messages.join("\n")

        errors = []
        connection do |ssh|
          ssh.exec!("rm -r '#{remote_path}'") do |ch, stream, data|
            errors << data if stream == :stderr
          end
        end
        unless errors.empty?
          raise Errors::Storage::SCP::SSHError,
            "Net::SSH reported the following errors:\n" +
              errors.join("\n"), caller(1)
        end
      end

      ##
      # Creates (if they don't exist yet) all the directories on the remote
      # server in order to upload the backup file. Net::SCP does not support
      # paths to directories that don't yet exist when creating new directories.
      # Instead, we split the parts up in to an array (for each '/') and loop through
      # that to create the directories one by one. Net::SCP raises an exception when
      # the directory it's trying ot create already exists, so we have rescue it
      def create_remote_directories(ssh)
        path_parts = Array.new
        remote_path.split('/').each do |path_part|
          path_parts << path_part
          ssh.exec!("mkdir '#{path_parts.join('/')}'")
        end
      end

    end
  end
end
