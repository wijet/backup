# encoding: utf-8

##
# Use Bundler
require 'rubygems' if RUBY_VERSION < '1.9'
require 'bundler/setup'

##
# Load Backup
require 'backup'

module Backup
  module SpecLive
    PATH = File.expand_path('..', __FILE__)
    # to archive local backups, etc...
    TMP_PATH = PATH + '/tmp'

    config = PATH + '/backups/config.yml'
    if File.exist?(config)
      CONFIG = YAML.load_file(config)
    else
      puts "The 'spec-live/backups/config.yml' file is required."
      puts "Use 'spec-live/backups/config.yml.template' to create one"
      exit!
    end

    module ExampleHelpers

      def h_set_trigger(trigger)
        Backup::Model.current = nil
        Backup::Model.extension = 'tar'
        Logger.messages.clear

        Backup.send(:remove_const, :TRIGGER) if defined? Backup::TRIGGER
        Backup.send(:const_set, :TRIGGER, trigger)

        Backup.send(:remove_const, :TIME) if defined? Backup::TIME
        Backup.send(:const_set, :TIME, Time.now.strftime("%Y.%m.%d.%H.%M.%S"))

        FileUtils.mkdir_p(File.join(Backup::DATA_PATH, Backup::TRIGGER))

        Backup::Finder.new(trigger).find
      end

      def h_reset_data_paths!
        paths = %w{ DATA_PATH
                    LOG_PATH
                    CACHE_PATH
                    TMP_PATH
                }.map {|c| Backup.const_get(c) } +
                [Backup::SpecLive::TMP_PATH]
        spec_live_dir = File.expand_path('..', __FILE__)
        paths.each do |path|
          # Rule #1: Do No Harm.
          unless path.start_with? spec_live_dir
            warn "#{c} => #{path}\nIt should have started with #{spec_live_dir}"
            exit!
          end
          FileUtils.rm_rf(path)
          FileUtils.mkdir_p(path)
        end
      end

    end # ExampleHelpers
  end

  %w{ USER
      HOME
      PATH
      DATA_PATH
      CONFIG_FILE
      LOG_PATH
      CACHE_PATH
      TMP_PATH }.each {|c| remove_const(c) }

  USER = SpecLive::CONFIG['config']['user']
  HOME = SpecLive::CONFIG['config']['home']
  PATH = SpecLive::PATH + '/backups'
  CONFIG_FILE = PATH + '/config.rb'
  DATA_PATH   = PATH + '/data'
  LOG_PATH    = PATH + '/log'
  CACHE_PATH  = PATH + '/cache'
  TMP_PATH    = PATH + '/tmp'

  Logger::QUIET = true unless ENV['VERBOSE']
end

##
# Use Mocha to mock with RSpec
require 'rspec'
RSpec.configure do |config|
  config.mock_with :mocha
  config.include Backup::SpecLive::ExampleHelpers
  config.before(:each) do
    h_reset_data_paths!
    Backup::Logger.clear!
    if ENV['VERBOSE']
      /spec-live\/(.*):/ =~ self.example.metadata[:example_group][:block].inspect
      puts "\n\nSPEC: #{$1}"
      puts "DESC: #{self.example.metadata[:full_description]}"
      puts '-' * 78
    end
  end
end

puts "\n\nRuby version: #{RUBY_DESCRIPTION}\n\n"
