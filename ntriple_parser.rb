$KCODE = 'u'
require 'rubygems'
require 'strscan'
require 'iconv'
require 'jcode'
require 'uri'
require 'active_support'
require 'lcsh_labels'

class UTF8Parser < StringScanner
  STRING = /(([\x0-\x1f]|[\\\/bfnrt]|\\u[0-9a-fA-F]{4}|[\x20-\xff])*)/nx
  UNPARSED = Object.new      
  UNESCAPE_MAP = Hash.new { |h, k| h[k] = k.chr }
  UNESCAPE_MAP.update({
    ?"  => '"',
    ?\\ => '\\',
    ?/  => '/',
    ?b  => "\b",
    ?f  => "\f",
    ?n  => "\n",
    ?r  => "\r",
    ?t  => "\t",
    ?u  => nil, 
  })        
  UTF16toUTF8 = Iconv.new('utf-8', 'utf-16be')                
  def initialize(str)
    super(str)
    @string = str
  end
  def parse_string
    if scan(STRING)
      return '' if self[1].empty?
      string = self[1].gsub(%r((?:\\[\\bfnrt"/]|(?:\\u(?:[A-Fa-f\d]{4}))+|\\[\x20-\xff]))n) do |c|
        if u = UNESCAPE_MAP[$&[1]]
          u
        else # \uXXXX
          bytes = ''
          i = 0
          while c[6 * i] == ?\\ && c[6 * i + 1] == ?u
            bytes << c[6 * i + 2, 2].to_i(16) << c[6 * i + 4, 2].to_i(16)
            i += 1
          end
          UTF16toUTF8.iconv(bytes)
        end
      end
      if string.respond_to?(:force_encoding)
        string.force_encoding(Encoding::UTF_8)
      end
      string
    else
      UNPARSED
    end
  rescue Iconv::Failure => e
    raise GeneratorError, "Caught #{e.class}: #{e}"
  end  
end

class TripleParser
  attr_reader :ntriple, :subject, :predicate, :data_type, :language, :literal
  attr_accessor :object
  def initialize(line)
    @ntriple = line
    parse_ntriple
  end
  
  def parse_ntriple
    scanner = StringScanner.new(@ntriple)
    @subject = scanner.scan_until(/> /)
    @subject.sub!(/^</,'')
    @subject.sub!(/> $/,'')
    @predicate = scanner.scan_until(/> /)
    @predicate.sub!(/^</,'')
    @predicate.sub!(/> $/,'')
    if scanner.match?(/</)
      @object = scanner.scan_until(/>\s?\.\n/)
      @object.sub!(/^</,'')
      @object.sub!(/>\s?\.\n/,'')
      @literal = false
    else
      @literal = true
      scanner.getch
      @object = scanner.scan_until(/("\s?\.\n)|("@[A-z])|("\^\^)/)
      scanner.pos=(scanner.pos-2)
      @object.sub!(/"..$/,'')
      uscan = UTF8Parser.new(@object)
      @object = uscan.parse_string
      if scanner.match?(/@/)
        scanner.getch
        @language = scanner.scan_until(/\s?\.\n/)
        @language.sub!(/\s?\.\n/,'')
      elsif scanner.match?(/\^\^/)
        scanner.skip_until(/</)
        @data_type = scanner.scan_until(/>/)
        @data_type.sub!(/>$/,'')
      end
    end
  end
end



file = File.open("/Users/rosssinger/Downloads/20090604_164455.nt",'r').readlines

def lcsh_to_platform_uri(uri)
  platform_uri = URI.parse(uri)
  platform_uri.host = 'lcsubjects.org'
  platform_uri.path.sub!(/\/authorities\//,"/subjects/")
  return platform_uri.to_s
end
Label.auto_migrate!
puts "#{file.length} total triples"

file.each do | triple |
  parser = TripleParser.new(triple)
  new_uri = lcsh_to_platform_uri(parser.subject)
  next unless ["http://www.w3.org/2004/02/skos/core#prefLabel", "http://www.w3.org/2004/02/skos/core#altLabel", "http://www.w3.org/2004/02/skos/core#hiddenLabel"].index(parser.predicate)
  label = Label.new(:uri=>new_uri,:label=>parser.object)
  label.save
end



