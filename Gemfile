# frozen_string_literal: true

source 'https://rubygems.org'

# Look in asciidoctor-epub3.gemspec for runtime and development dependencies.
gemspec

gem 'asciidoctor', ENV['ASCIIDOCTOR_VERSION'], require: false if ENV.key? 'ASCIIDOCTOR_VERSION'

group :optional do
  gem 'epubcheck-ruby', '4.2.2.0'
  gem 'kindlegen', (Gem::Version.new RUBY_VERSION) < (Gem::Version.new '2.4.0') ? '3.0.3' : '3.0.5'
  gem 'pygments.rb', '1.2.1'
end

group :docs do
  gem 'yard', require: false
end
