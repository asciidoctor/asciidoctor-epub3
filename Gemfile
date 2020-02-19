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
  gem 'epubcheck-ruby', '~> 4.2.2.0'
  # We would like to make kindlegen a runtime dependency, but can't because of the way asciidoctorj-epub3 packaging works
  # See https://github.com/asciidoctor/asciidoctor-epub3/issues/288
  gem 'kindlegen', '~> 3.0.3'
  gem 'pygments.rb', '1.2.1'
end

group :docs do
  gem 'yard', require: false
end
