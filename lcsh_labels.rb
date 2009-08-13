require 'rubygems'
require 'dm-core'
DataMapper.setup(:default, "sqlite3:///#{Dir.pwd}/lcsh_labels.db")
class Label
  include DataMapper::Resource
  property :id, Serial
  property :uri, String, :index => true
  property :label, String, :index => true
end  