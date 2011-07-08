require 'rubygems'
require 'enhanced_marc'
require 'rdf'
require 'rdf/ntriples'
require 'sru'
require 'sequel'
require 'yaml'
require 'isbn/tools'

CONFIG = YAML.load_file('config/config.yml')
DB = Sequel.connect(CONFIG['database'])
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
  def self.extended(o)
    o.set_type case
    when o.record.is_manuscript? then RDF::BIBO.Manuscript
    when o.record.is_conference? then RDF::BIBO.Proceedings
    else
      RDF::BIBO.Book
    end
  end
end

module SerialModeler
  def self.extended(o)
    t = nil
    if n = o.record.nature_of_work
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
    unless t
      if st = o.record.serial_type
        t = case
        when 'a' then RDF::BIBO.Collection
        when 'm' then RDF::BIBO.Series
        when 'n' then RDF::BIBO.Newspaper
        when 'p' then RDF::BIBO.Periodical
        when 'w' then RDF::BIBO.Website
        end
      end
    end
    t = RDF::BIBO.Periodical unless t
    o.set_type(t)  
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
    when MARC::BookRecord then extend(BookModeler)
    when MARC::SerialRecord then extend(SerialModeler)
    end
    gather_identifiers
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
  
  def gather_identifiers
    fld_list = ['010', '020','022']
    @record.each_by_tag(fld_list) do |field|
      case field.tag
      when '010' then model_lccn(field)
      when '020' then model_isbn(field)
      when '022' then model_isbn(field)
      end
    end
  end
  
  def model_lccn(f)
    return unless lccn = f['a']
    lccn.strip!
    prefix = nil
    year = nil
    serial = nil
    if prefix_m = lccn.match(/^([a-z]{1,3})(\s|\d)/)
      prefix = prefix_m[1]
    year_first_digit = lccn.match(/^[a-z]{0,3}\s*(\d)/)
    if year_first_digit
      year_m = case year_first_digit[1]
      when "2" then lccn.match(/^[a-z]{0,3}\s*(\d{4})/)
      else
        lccn.match(/^[a-z]{0,3}\s*(\d{2})/)
      end
      year = year_m[1] if year_m
    end
  end
end
  