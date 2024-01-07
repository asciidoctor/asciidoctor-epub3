# frozen_string_literal: true

require 'English'

begin
  require 'bundler/gem_tasks'
  $default_tasks << :build # rubocop:disable Style/GlobalVars
rescue LoadError
  warn $ERROR_INFO.message
end
