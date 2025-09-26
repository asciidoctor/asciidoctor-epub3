# frozen_string_literal: true

require_relative 'lib/asciidoctor-epub3/version'
require 'open3' unless defined? Open3

Gem::Specification.new do |s|
  s.name = 'asciidoctor-epub3'
  s.version = Asciidoctor::Epub3::VERSION

  s.summary = 'Converts AsciiDoc documents to EPUB3 e-book format'
  s.description = <<~EOS
    An extension for Asciidoctor that converts AsciiDoc documents to EPUB3 e-book format.
  EOS

  s.authors = ['Dan Allen', 'Sarah White']
  s.email = 'dan@opendevise.com'
  s.homepage = 'https://github.com/asciidoctor/asciidoctor-epub3'
  s.license = 'MIT'

  s.required_ruby_version = '>= 2.7.0'

  files = begin
    (result = Open3.popen3('git ls-files -z') { |_, out| out.read }.split %(\0)).empty? ? Dir['**/*'] : result
  rescue StandardError
    Dir['**/*']
  end
  s.files = files.grep %r{^(?:(?:data/(?:fonts|images|styles)|lib)/.+|Gemfile|Rakefile|LICENSE|(?:CHANGELOG|NOTICE|README)\.adoc|\.yardopts|#{s.name}\.gemspec)$}
  s.executables = %w[asciidoctor-epub3]

  s.require_paths = ['lib']

  s.add_dependency 'asciidoctor', '~> 2.0'
  s.add_dependency 'gepub', '>= 1.0', '< 2.1'
  s.add_dependency 'mime-types', '~> 3.0'

  # TODO: switch to 'sass-embedded' when we drop Ruby 2.5 support
  s.add_dependency 'sass'

  s.add_development_dependency 'asciidoctor-diagram', '~> 3.0'
  s.add_development_dependency 'asciidoctor-diagram-ditaamini', '~> 1.0'
  s.add_development_dependency 'asciidoctor-diagram-plantuml', '~> 1.2025'
  s.add_development_dependency 'asciimath', '~> 2.0'
  s.add_development_dependency 'coderay', '~> 1.1.0'
  s.add_development_dependency 'concurrent-ruby', '~> 1.0'
  s.add_development_dependency 'epubcheck-ruby', '~> 5.3.0.0'
  s.add_development_dependency 'pygments.rb', '~> 4.0.0'
  s.add_development_dependency 'rake', '~> 13.3.0'
  s.add_development_dependency 'rouge', '~> 4.6'
  s.add_development_dependency 'rspec', '~> 3.13.0'
  s.add_development_dependency 'rubocop', '~> 1.81.0'
  s.add_development_dependency 'rubocop-rake', '~> 0.7.1'
  s.add_development_dependency 'rubocop-rspec', '~> 3.3'
  s.add_development_dependency 'slim', '~> 5.0'
  s.add_development_dependency 'tilt', '~> 2.0'
end
