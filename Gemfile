# frozen_string_literal: true

source 'https://rubygems.org'

# Look in asciidoctor-epub3.gemspec for runtime and development dependencies.
gemspec

group :optional do
  # epubcheck-ruby might be safe to be converted into runtime dependency,
  # but could have issues when packaged into asciidoctorj-epub3
  gem 'epubcheck-ruby', '~> 5.1.0.0'
end
