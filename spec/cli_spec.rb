# frozen_string_literal: true

require_relative 'spec_helper'

describe 'asciidoctor-epub3' do
  it 'exits with 0 when prints version' do
    out, _, res = run_command asciidoctor_epub3_bin, '--version'
    expect(res.exitstatus).to eq(0)
    expect(out).to include %(Asciidoctor EPUB3 #{Asciidoctor::Epub3::VERSION} using Asciidoctor #{Asciidoctor::VERSION})
  end

  it 'exits with 1 when given nonexistent path' do
    _, err, res = run_command asciidoctor_epub3_bin, '/nonexistent'
    expect(res.exitstatus).to eq(1)
    expect(err).to match(/input file \/nonexistent( is)? missing/)
  end

  it 'converts sample book to epub and validates it' do
    infile = example_file 'sample-book.adoc'
    outfile = temp_file 'sample-book.epub'

    _, err, res = run_command asciidoctor_epub3_bin, '-a', 'ebook-validate', infile, '-o', outfile
    expect(res.exitstatus).to eq(0)
    # TODO: https://github.com/asciidoctor/asciidoctor-epub3/issues/196
    expect(err).to include 'invalid reference to anchor in unknown chapter: NOTICE'
    expect(File).to exist(outfile)
  end

  it 'converts sample book to mobi' do
    skip_if_darwin

    infile = example_file 'sample-book.adoc'
    outfile = temp_file 'sample-book.mobi'

    _, err, res = run_command asciidoctor_epub3_bin, '-a', 'ebook-format=mobi', infile, '-o', outfile
    expect(res.exitstatus).to eq(0)
    # TODO: https://github.com/asciidoctor/asciidoctor-epub3/issues/196
    expect(err).to include 'invalid reference to anchor in unknown chapter: NOTICE'
    expect(File).to exist(outfile)
  end
end
