# frozen_string_literal: true

require 'asciidoctor'
require 'asciidoctor/extensions'
require 'gepub'
require_relative 'asciidoctor-epub3/ext'
require_relative 'asciidoctor-epub3/converter'

# We need to be able to write files with unicode names. See https://github.com/asciidoctor/asciidoctor-epub3/issues/217
::Zip.unicode_names = true
