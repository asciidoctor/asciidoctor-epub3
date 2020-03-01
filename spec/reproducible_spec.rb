# frozen_string_literal: true

require_relative 'spec_helper'

describe Asciidoctor::Epub3::Converter do
  it 'produces stable output for reproducible books' do
    out_file1 = temp_file 'book1.epub'
    out_file2 = temp_file 'book2.epub'
    to_epub fixture_file('reproducible/book.adoc'), to_file: out_file1.to_s
    sleep 2
    to_epub fixture_file('reproducible/book.adoc'), to_file: out_file2.to_s
    expect(FileUtils.compare_file(out_file1.to_s, out_file2.to_s)).to be true
  end

  it %(doesn't include date for reproducible books) do
    book, = to_epub fixture_file('reproducible/book.adoc')
    expect(book.date).to be_nil
  end

  it 'uses fixed lastmodified date for reproducible books' do
    book, = to_epub fixture_file('reproducible/book.adoc')
    expect(Time.parse(book.lastmodified.content)).to eq (Time.at 0).utc
  end

  it 'sets mod and creation dates to match SOURCE_DATE_EPOCH environment variable' do
    old_source_date_epoch = ENV.delete 'SOURCE_DATE_EPOCH'
    begin
      ENV['SOURCE_DATE_EPOCH'] = '1234123412'
      book, = to_epub fixture_file('minimal/book.adoc')
      expect(book.date.content).to eq('2009-02-08T20:03:32Z')
      expect(book.lastmodified.content).to eq('2009-02-08T20:03:32Z')
    ensure
      if old_source_date_epoch
        ENV['SOURCE_DATE_EPOCH'] = old_source_date_epoch
      else
        ENV.delete 'SOURCE_DATE_EPOCH'
      end
    end
  end
end
