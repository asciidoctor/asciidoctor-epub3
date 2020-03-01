# frozen_string_literal: true

require_relative 'spec_helper'

describe 'asciidoctor-epub3' do
  it 'exits with 0 when prints version' do
    out, _, res = run_command asciidoctor_epub3_bin, '--version'
    expect(res.exitstatus).to eq(0)
    expect(out).to include %(Asciidoctor EPUB3 #{Asciidoctor::Epub3::VERSION} using Asciidoctor #{Asciidoctor::VERSION})
  end

  it 'exits with 1 when given nonexistent path' do
    _, err, res = to_epub Pathname.new('/nonexistent')
    expect(res.exitstatus).to eq(1)
    expect(err).to match(/input file \/nonexistent( is)? missing/)
  end

  it 'exits with 1 when epub validation fails on Asciidoctor >= 1.5.7 with --failure-level=ERROR' do
    skip_unless_has_logger

    _, err, res = run_command asciidoctor_epub3_bin,
        '--failure-level=ERROR',
        '-a', 'ebook-validate',
        fixture_file('invalid.adoc').to_s,
        '-o', temp_file('invalid.epub').to_s
    expect(res.exitstatus).to eq(1)
    # Error from epubcheck
    expect(err).to include 'ERROR(RSC-012)'
  end

  it 'converts sample book to epub and validates it' do
    in_file = example_file 'sample-book.adoc'
    out_file = temp_file 'sample-book.epub'

    _, err, res = to_epub in_file, out_file
    expect(res.exitstatus).to eq(0)
    expect(err).not_to include 'ERROR'
    expect(err).not_to include 'invalid reference'
    expect(File).to exist(out_file)
  end

  it 'converts sample book to mobi' do
    in_file = example_file 'sample-book.adoc'
    out_file = temp_file 'sample-book.mobi'

    _, err, res = to_mobi in_file, out_file
    expect(res.exitstatus).to eq(0)
    expect(err).not_to include 'ERROR'
    expect(err).not_to include 'invalid reference'
    expect(File).to exist(out_file)
  end

  it 'prints errors to stderr when converts invalid book to epub' do
    _, err, res = to_epub fixture_file('invalid.adoc'), temp_file('invalid.epub')
    expect(res.exitstatus).to eq(0)
    # Error from epubcheck
    expect(err).to include 'ERROR(RSC-012)'
    # Error from converter.rb
    expect(err).to include 'EPUB validation failed'
  end

  it 'prints errors to stderr when converts invalid book to mobi' do
    _, err, res = to_mobi fixture_file('invalid.adoc'), temp_file('invalid.mobi')
    expect(err).to include 'ERROR'
    expect(res.exitstatus).to eq(0)
  end

  def to_mobi in_file, out_file
    skip_unless_has_kindlegen
    run_command asciidoctor_epub3_bin, '-a', 'ebook-format=mobi', in_file.to_s, '-o', out_file.to_s
  end

  def to_epub in_file, out_file = nil
    argv = asciidoctor_epub3_bin + ['-a', 'ebook-validate', in_file.to_s]
    argv += ['-o', out_file.to_s] unless out_file.nil?
    run_command argv
  end
end
