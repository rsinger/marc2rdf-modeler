require 'rubygems'
require 'enhanced_marc'
require 'rdf'
require 'rdf/ntriples'
require 'sru'
require 'sequel'
require 'yaml'

CONFIG = YAML.load_file('config/config.yml')
DB = Sequel.connect(DB['database'])
# Initialize the vocabularies we will be drawing from
module RDF
  class BIBO < RDF::Vocabulary("http://purl.org/ontology/bibo/");end
  class RDA < RDF::Vocabulary("http://RDVocab.info/Elements/");end
  class RDAG2 < RDF::Vocabulary("http://RDVocab.info/ElementsGr2/");end
  class DCAM < RDF::Vocabulary("http://purl.org/dc/dcam/");end
  class FRBR < RDF::Vocabulary("http://purl.org/vocab/frbr/core#");end
  class BIO < RDF::Vocabulary("http://purl.org/vocab/bio/0.1/");end
  class OV < RDF::Vocabulary("http://open.vocab.org/terms/");end
end

class String
  def slug
    slug = self.gsub(/[^A-z0-9\s\-]/,"")
    slug.gsub!(/\s/,"_")
    slug.downcase.strip_leading_and_trailing_punct
  end  
  def strip_trailing_punct
    self.sub(/[\.:,;\/\s]\s*$/,'').strip
  end
  def strip_leading_and_trailing_punct
    str = self.sub(/[\.:,;\/\s\)\]]\s*$/,'').strip
    return str.strip.sub(/^\s*[\.:,;\/\s\(\[]/,'')
  end  
  def lpad(count=1)
    "#{" " * count}#{self}"
  end
  
end
class IdentifierFieldNotFoundError < Exception;end
module BookModeler
  def self.included(o)
    case
    when o.is_manuscript? then o.set_type(RDF::BIBO.Manuscript)
    when o.is_conference? then o.set_type(RDF::BIBO.Proceedings)
    else
      o.set_type(RDF::BIBO.Book)
    end
  end
end

module SerialModeler
  def self.included(o)
    t = nil
    if n = o.nature_of_work
      t = case
      when 'd' then RDF::BIBO.ReferenceSource
      when 'e' then RDF::BIBO.ReferenceSource
      when 'g' then RDF::BIBO.LegalDocument
      when 'j' then RDF::BIBO.Patent
      when 'l' then RDF::BIBO.Legislation
      when 'm' then RDF::BIBO.Thesis
      when 't' then RDF::BIBO.Report
      when 'u' then RDF::BIBO.Standard
      when 'v' then RDF::BIBO.LegalCaseDocument
      when 'w' then RDF::BIBO.Report
      when 'x' then RDF::BIBO.Report
      when 'z' then RDF::BIBO.Treaty
      end
    end
  end  
end
class RDFModeler
  attr_reader :record, :statements, :uri
  def initialize(record)
    @record =  record
    construct_uri
    @statements = []
  end
  
  def parse
    case @record
    when MARC::BookRecord then include(BookModeler)
    when MARC::SerialRecord then include(SerialModeler)
    end
  end
  
  def set_type(t)
    @statements << RDF::Statement.new(@uri, RDF.type, t)
  end
  
  def construct_uri
    @uri = RDF::URI.intern(CONFIG['uri']['base'] + CONFIG['uri']['resource_path'])
    id = @record[CONFIG['uri']['resource_identifier_field']]
    raise IdentifierFieldNotFoundError unless id
    @uri += id.value.strip.slug
  end
end
  