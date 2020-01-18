# -*- encoding: utf-8 -*-
require File.expand_path '../lib/asciidoctor-epub3/version', __FILE__

require 'rake/clean'

default_tasks = []

begin
  require 'bundler/gem_tasks'
  default_tasks << :build

  # Enhance the release task to create an explicit commit for the release
  #Rake::Task[:release].enhance [:commit_release]

  # NOTE you don't need to push after updating version and committing locally
  # WARNING no longer works; it's now necessary to get master in a state ready for tagging
  task :commit_release do
    Bundler::GemHelper.new.send :guard_clean
    sh %(git commit --allow-empty -a -m 'Release #{Asciidoctor::Epub3::VERSION}')
  end
rescue LoadError
end

begin
  require 'rdoc/task'
  Rake::RDocTask.new do |t|
    t.rdoc_dir = 'rdoc'
    t.title = %(Asciidoctor EPUB3 #{Asciidoctor::Epub3::VERSION})
    t.main = %(README.adoc)
    t.rdoc_files.include 'README.adoc', 'LICENSE.adoc', 'NOTICE.adoc', 'lib/**/*.rb', 'bin/**/*'
  end
rescue LoadError
end

begin
  require 'rspec/core/rake_task'
  RSpec::Core::RakeTask.new(:spec)
rescue LoadError
end

task :default => default_tasks unless default_tasks.empty?
