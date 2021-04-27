# frozen_string_literal: true

source 'https://rubygems.org'

# Look in asciidoctor-epub3.gemspec for runtime and development dependencies.
gemspec

if ENV.key? 'ASCIIDOCTOR_VERSION'
  gem 'asciidoctor', ENV['ASCIIDOCTOR_VERSION'], require: false
  # Newer asciidoctor-diagram 1.5.x require asciidoctor >=1.5.7
  gem 'asciidoctor-diagram', '1.5.16', require: false if Gem::Version.new(ENV['ASCIIDOCTOR_VERSION']) < Gem::Version.new('2.0.0')
end

group :optional do
  # epubcheck-ruby might be safe to be converted into runtime dependency, but could have issues when packaged into asciidoctorj-epub3
  gem 'epubcheck-ruby', '~> 4.2.5.0'
  # Kindlegen is unavailable neither for 64-bit MacOS nor for ARM
  gem 'kindlegen', '~> 3.1.0' unless RbConfig::CONFIG['host_os'] =~ /darwin/
end
