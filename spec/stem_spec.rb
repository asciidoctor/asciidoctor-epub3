# frozen_string_literal: true

require_relative 'spec_helper'

describe 'Asciidoctor::Epub3::Converter - Stem' do
  it 'supports mathml stem blocks' do
    book, = to_epub fixture_file('stem.adoc')
    chapter = book.item_by_href 'stem.xhtml'
    expect(chapter).not_to be_nil
    expect(chapter.content).to include '<figcaption>Math</figcaption>
<div class="content">
<mml:math><mml:mi>y</mml:mi><mml:mo>=</mml:mo><mml:msup><mml:mi>x</mml:mi><mml:mn>2</mml:mn></mml:msup><mml:msqrt><mml:mn>4</mml:mn></mml:msqrt></mml:math>
</div>
</figure>'
  end

  it 'supports inline mathml' do
    book, = to_epub fixture_file('inline-stem.adoc')
    chapter = book.item_by_href 'inline-stem.xhtml'
    expect(chapter).not_to be_nil
    expect(chapter.content).to include 'Inline stem: <code class="literal"><mml:math><mml:mi>y</mml:mi><mml:mo>=</mml:mo><mml:msup><mml:mi>x</mml:mi><mml:mn>2</mml:mn></mml:msup><mml:msqrt><mml:mn>4</mml:mn></mml:msqrt></mml:math></code>'
  end
end
