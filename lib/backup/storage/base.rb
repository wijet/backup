# encoding: utf-8

module Backup
  module Storage
    class Base
      include Backup::Configuration::Helpers

      ##
      # The time when the backup initiated (in format: 2011.02.20.03.29.59)
      attr_accessor :time

      ##
      # Sets the limit to how many backups to keep in the remote location.
      # If exceeded, the oldest will be removed to make room for the newest
      attr_accessor :keep

      # Temporarily holds the configuration block used to instantiate the
      # storage object. Used for updating storage objects loaded from YAML
      # during backup rotation in #cycle!
      attr_accessor :configure_block

      ##
      # Contains an array of chunk suffixes (if any)
      # If none are set, this will be an empty array, in which case Backup assumes
      # we haven't been splitting the backup in to multiple chunks. The storage object
      # will only attempt to transfer/remove chunks if this array contains chunk suffixes.
      attr_accessor :chunk_suffixes

      ##
      # Super method for the child classes' perform! method. "super" should
      # always be invoked from the child classes' perform! method to ensure that the
      # @chunk_suffixes array gets set to the storage object, which will be used to transfer all the
      # chunks to the remote location, rather than the single backup file. Also, this will be persisted
      # and loaded back in during the cycling process, so it gets properly deleted from the remote location.

      ##
      # (Optional)
      # User-defined string used to uniquely identify multiple storages of the same type.
      # This will be appended to the YAML storage file used for cycling backups.
      attr_accessor :storage_id

      ##
      # Set to Backup::Version.current just before the object is stored
      # in the YAML file for cycling. This way, we know when the object
      # is loaded from the YAML file, which version of Backup stored it.
      attr_reader :version

      def perform!
        @chunk_suffixes ||= Backup::Model.chunk_suffixes
      end

      ##
      # Creates a new instance of the storage object
      def initialize(storage_id = nil, &block)
        @configure_block = block
        @storage_id = storage_id
        configure!
      end

      ##
      # Return the storage name, with optional storage_id
      def storage_name
        self.class.to_s.sub('Backup::', '') +
            (storage_id ? " (#{storage_id})" : '')
      end

      ##
      # Returns the full filename of the processed backup file
      def filename
        @filename ||= File.basename(Backup::Model.file)
      end

      ##
      # Returns the local path
      def local_path
        TMP_PATH
      end

      ##
      # Returns an array of backup chunks
      def chunks
        chunk_suffixes.map do |chunk_suffix|
          "#{ filename }-#{ chunk_suffix }"
        end.sort
      end

      ##
      # Returns a block with two arguments: "local_file, remote_file"
      # The local_file is the full file name: "2011.08.30.11.00.02.backup.tar.gz.enc"
      # The remote_file is the full file name, minus the timestamp: "backup.tar.gz.enc"
      def files_to_transfer
        if chunks?
          chunks.each do |chunk|
            yield chunk, chunk[20..-1]
          end
        else
          yield filename, filename[20..-1]
        end
      end

      alias :transferred_files :files_to_transfer

      ##
      # Returns true if we're working with chunks
      # that were splitted by Backup
      def chunks?
        chunk_suffixes.is_a?(Array) and chunk_suffixes.count > 0
      end

      ##
      # Provider defaults to false. Overridden when using a service-based
      # storage such as Amazon S3, Rackspace Cloud Files or Dropbox
      def provider
        false
      end

    private

      ##
      # Configure the storage object, using optional configuration block
      # Uses #pre_configure to set defaults (if any exist) and then evaluates
      # the optional configuration block which may overwrite these defaults.
      # Then uses #post_configure to adjust the configuration as needed.
      #
      # This method is also used to update storage objects loaded from the
      # YAML data storage file used for backup rotation in #cycle!
      def configure!
        pre_configure
        instance_eval(&@configure_block) if @configure_block
        post_configure
        self
      end

      ##
      # Set configuration defaults before evaluating configuration block.
      # Each subclass may perform additional actions after calling super()
      def pre_configure
        load_defaults!
      end

      ##
      # Adjust configuration after evaluating configuration block.
      # Each subclass may perform additional actions after calling super()
      def post_configure
        @time ||= TIME
      end

      ##
      # Update the configuration with the given +configure_block+
      # This is to update the configuration for this storage object
      # once it's been loaded from the YAML storage file (within #cycle!)
      # so that cycling operations can be performed using the latest
      # configuration from the current backup job.
      def update!(configure_block)
        upgrade_if_needed!
        instance_exec(configure_block) do |block|
          @configure_block = block; configure!
        end
      end

      ##
      # Upgrades the format of an object loaded from the YAML storage file
      # if it was stored with a previous, incompatible version of Backup,
      # before it is updated using the new configure_block in #update!
      def upgrade_if_needed!
        return if version == Backup::Version.current
        case
        when version.nil? # <= 3.0.19
          @filename = @remote_file
          @chunk_suffixes = []
          clean!
        else; # upgrade not required
        end
      end

      ##
      # Clear all attributes except those which need to be stored
      # in the YAML storage file for cycling, and version stamp it.
      def clean!
        stored_attrs = [:@filename, :@time, :@chunk_suffixes]
        (instance_variables.map(&:to_sym) - stored_attrs).each do |var|
          remove_instance_variable var
        end
        @version = Backup::Version.current
      end

      ##
      # Checks the persisted storage data by type (S3, CloudFiles, SCP, etc)
      # to see if the amount of stored backups is greater than the amount of
      # backups allowed. If this is the case it'll invoke the #remove! method
      # on each of the oldest backups that exceed the storage limit (specified
      # by @keep). After that it'll re-assign the objects variable with an
      # array of objects that still remain after the removal of the older
      # objects and files (that exceeded the @keep range). And finally these
      # remaining objects will be converted to YAML format and are written back
      # to the YAML file.
      # Each remaining storage object's attributes will be updated using the
      # defaults and configuration block defined for the current backup job
      # in case the storage location is changed or credentials are updated.
      def cycle!
        return unless keep.to_i > 0
        type           = self.class.name.split("::").last
        storage_object = Backup::Storage::Object.new(type, storage_id)
        objects        = storage_object.load
        objects.each {|object| object.send(:update!, @configure_block) }
        objects.unshift(self)
        if objects.count > keep
          objects_to_remove = objects[keep..-1]
          objects_to_remove.each do |object|
            Logger.message "#{storage_name} started removing (cycling) " +
                "'#{ object.filename }'."
            begin
              object.send(:remove!)
            rescue => err
              Logger.warn Errors::Storage::CycleError.wrap(err,
                  "#{storage_name} failed to remove '#{object.filename}'")
            end
          end
          objects = objects - objects_to_remove
        end
        objects.each {|object| object.send(:clean!) }
        storage_object.write(objects)
      end

    end
  end
end
