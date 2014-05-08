require 'asciidoctor'
require 'asciidoctor/extensions'

module Asciidoctor
module Epub3
class SpineItemProcessor < ::Asciidoctor::Extensions::IncludeProcessor
  def initialize document
    @document = document
  end

  # NOTE only fires for includes in master document if registered directly on the instance of the master document
  def process reader, target, attributes
    master_doc = @document
    unless ::File.exist?(include_file = (master_doc.normalize_system_path target, reader.dir, nil, target_name: 'include file'))
      warn %(asciidoctor: WARNING: #{reader.line_info}: include file not found: #{include_file})
      return
    end
    inherited_attributes = master_doc.attributes.dup
    %w(master doctitle docfile docdir docname).each {|key| inherited_attributes.delete key }

    # parse header to get author information
    spine_item_doc_meta = ::Asciidoctor.load_file include_file,
        safe: master_doc.safe,
        backend: :epub3,
        doctype: :article,
        parse_header_only: true 

    # blank out author information if present in sub-document
    # FIXME this is a huge hack...we need a cleaner way to do this; perhaps an API method that retrieves all the author attribute names
    if spine_item_doc_meta.attr? 'author'
      %w(author firstname lastname email authorinitials authors authorcount).each {|key| inherited_attributes.delete key }
      idx = 1
      while inherited_attributes.key? %(author_#{idx})
        %W(author_#{idx} firstname_#{idx} lastname_#{idx} email_#{idx} authorinitials_#{idx}).each {|key| inherited_attributes.delete key }
        idx += 1
      end
    end

    # REVIEW reaching into converter to resolve document id feels like a hack; should happen in Asciidoctor parser
    # also, strange that "id" doesn't work here
    inherited_attributes['css-signature'] = spine_item_doc_meta.converter.resolve_document_id spine_item_doc_meta

    # NOTE can't assign master as parent document since there's too many assumptions in the processor
    spine_item_doc = ::Asciidoctor.load_file include_file,
        # setting base_dir breaks if outdir is not a subdirectory of master_doc.base_dir
        #base_dir: master_doc.base_dir,
        # NOTE won't write to correct directory if safe mode is :secure
        safe: master_doc.safe,
        backend: :epub3,
        doctype: :article,
        header_footer: true,
        attributes: inherited_attributes

    # TODO may need to reset attributes before leaving this method

    (master_doc.references[:spine] ||= []) << spine_item_doc
    # NOTE if there are attribute assignments between the include directives,
    # then this ordered list is not continguous, so bailing on the idea
    #reader.replace_line %(. link:#{::File.basename(spine_item_doc.attr 'outfile')}[#{spine_item_doc.doctitle}])
  end

  # handles? should get the attributes on include directive as the second argument
  def handles? target
    (@document.attr? 'master') && (ASCIIDOC_EXTENSIONS.include? ::File.extname(target))
  end

  # FIXME this method shouldn't be required
  def update_config config
    (@config ||= {}).update config
  end
end
end
end
