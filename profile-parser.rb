#!/usr/bin/env ruby

require 'terminal-table'
require 'colored'

class Namespace
  attr_accessor :object

  def initialize(namespace, object)
    @namespace = namespace.split('.')
    @object    = object
    @children  = {}
  end

  def add(ns, object)
    parts = ns.split('.')

    child_ns = parts[0..-2]
    child_id = parts.last

    if(parts == @namespace)
      # We are the object
      @object = object
    elsif @namespace == child_ns
      get(child_id).add(ns, object)
    else
      id = parts.drop(@namespace.size).first
      child = get(id)
      child.add(ns, object)
    end
  end

  def get(id)
    @children[id] ||= Namespace.new([@namespace, id].flatten.join('.'), nil)
  end

  def display
    print "  " * @namespace.size
    print "#{@namespace.join('.').green} "
    print @object.inspect
    puts
    @children.values.each(&:display)
  end
end

class Slice
  attr_reader :id
  attr_reader :time
end

class FunctionSlice < Slice
  attr_reader :function
  alias name function

  def parse(line)
    match = line.match(/([\d\.]+) Called (\S+): took ([\d\.]+) seconds/)
    @id       = match[1]
    @function = match[2]
    @time     = match[3].to_f
    self
  end

  def inspect
    time = "(#{@time} seconds)".yellow
    "function #{@function} #{time}"
  end
end

class ResourceSlice < Slice
  attr_reader :type
  alias name type
  attr_reader :title

  def parse(line)
    match = line.match(/([\d\.]+) Evaluated resource ([\w:]+)\[(.*)\]: took ([\d\.]+) seconds$/)

    @id    = match[1]
    @type  = match[2]
    @title = match[3]
    @time  = match[4].to_f

    self
  end

  def inspect
    time = "(#{@time} seconds)".yellow
    "resource #{@type}[#{@title}] #{time}"
  end
end

class OtherSlice < Slice
  attr_reader :name

  def parse(line)
    match = line.match(/PROFILE \[[a-z\d]+\] ([\d\.]+) (.*): took ([\d\.]+) seconds$/)
    @id = match[1]
    @name = match[2]
    @time = match[3]
    self
  end

  def inspect
    time = "(#{@time} seconds)".yellow
    "#{@name} #{time}"
  end
end

def parse(line)
  case line
  when /Called/
    FunctionSlice.new.parse(line)
  when /Evaluated resource/
    ResourceSlice.new.parse(line)
  else
    OtherSlice.new.parse(line)
  end
end

def process_group(title, slices)
  total = 0.0
  itemized_totals = Hash.new { |h, k| h[k] = 0.0 }

  slices.each do |slice|
    total += slice.time
    itemized_totals[slice.name] += slice.time
  end

  rows = itemized_totals.to_a.sort { |a, b| b[1] <=> a[1] }

  table = Terminal::Table.new(:headings => ["Source", "Time"], :rows => rows)

  puts "--- #{title} ---"
  puts "Total time: #{total}"
  puts "Itemized:"
  puts table
end

things = []

ARGF.each_line do |line|
  next unless line.match(/PROFILE/)

  # Strip off leader
  if (match = line.match(/(PROFILE.*)$/))
    things << parse(match[1])
  end
end

root = Namespace.new('', nil)

things.each do |thing|
  root.add(thing.id, thing)
end

root.display

funcalls = things.select { |thing| thing.is_a? FunctionSlice }
resevals = things.select { |thing| thing.is_a? ResourceSlice }

process_group("Function calls", funcalls)
process_group("Resource evaluations", resevals)

