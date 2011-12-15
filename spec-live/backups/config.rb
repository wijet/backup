
##
# Archive Job
archive_job = lambda do |archive|
  archive.add     File.expand_path('../../../lib/backup', __FILE__)
  archive.exclude File.expand_path('../../../lib/backup/storage', __FILE__)
end

##
# Configuration

Backup::Configuration::Storage::Local.defaults do |storage|
  storage.path = Backup::SpecLive::TMP_PATH
  storage.keep = 2
end

# SSH operations can be tested against 'localhost'
# To do this, in the config.yml file:
# - set username/password for your current user
# - set ip to 'localhost'
# Although optional, it's recommended you set the 'path'
# to the same path as Backup::SpecLive::TMP_PATH
# i.e. '/absolute/path/to/spec-live/tmp'
# This way, cleaning the "remote path" can be skipped.
Backup::Configuration::Storage::SCP.defaults do |storage|
  opts = SpecLive::CONFIG['storage']['scp']

  storage.username = opts['username']
  storage.password = opts['password']
  storage.ip       = opts['ip']
  storage.port     = opts['port']
  storage.path     = opts['path']
  storage.keep     = 2
end

Backup::Configuration::Notifier::Mail.defaults do |notifier|
  opts = SpecLive::CONFIG['notifier']['mail']

  notifier.on_success           = true
  notifier.on_warning           = true
  notifier.on_failure           = true

  notifier.delivery_method      = opts['delivery_method']
  notifier.from                 = opts['from']
  notifier.to                   = opts['to']
  notifier.address              = opts['address']
  notifier.port                 = opts['port'] || 587
  notifier.domain               = opts['domain']
  notifier.user_name            = opts['user_name']
  notifier.password             = opts['password']
  notifier.authentication       = opts['authentication'] || 'plain'
  notifier.enable_starttls_auto = opts['enable_starttls_auto'] || true
  notifier.sendmail             = opts['sendmail']
  notifier.sendmail_args        = opts['sendmail_args']
  notifier.mail_folder          = Backup::SpecLive::TMP_PATH
end


##
# Models

Backup::Model.new(:archive_local, 'test_label') do |model|
  archive :test_archive, &archive_job
  store_with Local
end

Backup::Model.new(:archive_scp, 'test_label') do |model|
  archive :test_archive, &archive_job
  store_with SCP
end

Backup::Model.new(:notifier_mail, 'test_label') do |model|
  notify_by Mail
end

Backup::Model.new(:notifier_mail_file, 'test_label') do |model|
  notify_by Mail do |mail|
    mail.to = 'test@backup'
    mail.delivery_method = :file
  end
end
