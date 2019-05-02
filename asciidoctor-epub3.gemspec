# -*- encoding: utf-8 -*-
require File.expand_path('lib/asciidoctor-epub3/version', File.dirname(__FILE__))
require 'open3' unless defined? Open3

Gem::Specification.new do |s|
  s.name = 'asciidoctor-epub3'
  s.version = Asciidoctor::Epub3::VERSION

  s.summary = 'Converts AsciiDoc documents to EPUB3 and KF8/MOBI (Kindle) e-book formats'
  s.description = <<-EOS
An extension for Asciidoctor that converts AsciiDoc documents to EPUB3 and KF8/MOBI (Kindle) e-book archives.
  EOS

  s.authors = ['Dan Allen', 'Sarah White']
  s.email = 'dan@opendevise.com'
  s.homepage = 'https://github.com/asciidoctor/asciidoctor-epub3'
  s.license = 'MIT'

  # NOTE required ruby version is informational only; it's not enforced since it can't be overridden and can cause builds to break
  #s.required_ruby_version = '>= 2.3.0'

  files = begin
    (result = Open3.popen3('git ls-files -z') {|_, out| out.read }.split %(\0)).empty? ? Dir['**/*'] : result
  rescue
    Dir['**/*']
  end
  s.files = files.grep %r/^(?:(?:data\/(?:fonts|images|styles)|lib)\/.+|Gemfile|Rakefile|(?:CHANGELOG|LICENSE|NOTICE|README)\.adoc|\.yardopts|#{s.name}\.gemspec)$/
  s.executables = %w(asciidoctor-epub3 adb-push-ebook)
  s.test_files = s.files.grep(/^(?:test|spec|feature)\/.*$/)

  s.require_paths = ['lib']

  s.add_development_dependency 'rake', '~> 12.3.2'

  s.add_runtime_dependency 'asciidoctor', '>= 1.5.0', '< 3.0.0'
  s.add_runtime_dependency 'gepub', '~> 1.0.3'
  s.add_runtime_dependency 'thread_safe', '~> 0.3.6'
  s.add_runtime_dependency 'concurrent-ruby', '~> 1.1.5'
end
