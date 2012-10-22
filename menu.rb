#!/usr/bin/env ruby
# dmenu²
# menu actions
#  "action_type
# menu shortcuts
#  .abbr

# there can be any number of special tags associated with the an item that 
# give some information about the item, or correspond to an action for that
# item. We treat the item names as identifiers scoped to a given action
# (our actions act as namespaces). There can be name overlap where a given
# name will correspond to the same item in some sense, but that isn't something
# that is explicitly coded.
#
# In general, an item's full name (with tags and all) is a query string into the
# database (that will be created), with each space-separated item being a field
# in the query. The fields are identified by their particular sigil (which is 
# given when the tag is created), with the exception of the short name which is
# unadorned, but always comes first in the full name and cannot be ommited for
# any entry.
#
# The database is written in prolog because it's what I know  best and because
# rdf relationships are easy to express in prolog.
#
# Whenever a query is perfomed for some action that requires exactly one item,
# a resolution menu should be presented to the user to choose a specific entry.
#
# Some predefined actions
#    rm:
#      this removes an item from the menu. it has to find the item's global id
#      by making a query sans "rm. The query could return more than one item in
#      which case a resolution menu will be brought up with the matches.
#    cs:
#      change the shortcut for an entry
#      
# Each is also associated with a global identifier that relates items in different
# namespaces. Global identifiers correspond to a unique combination of associated
# tags because, first of all, we filter out duplicates, and second duplicates would
# by definition do exactly the same thing when selected
#
# TODO:
# - data storage and modification
require_relative './data'
require 'tmail'
# default configs {{{
$SCREEN_WIDTH=500
$FONT_WIDTH=15 #in pixels
$BG_COLOR='"#000000"'
$FG_COLOR='"#12349f"'
$SEL_BG_COLOR=$FG_COLOR
$SEL_FG_COLOR=$BG_COLOR
$FONT='"Sazanami Mincho":pixelsize=' + $FONT_WIDTH.to_s
$LIST_ENTRIES_PER_PAGE = 15
# }}}

def my_dmenu (entries, prompt='dmenu2', height=entries.count, width=$SCREEN_WIDTH)
#width=$SCREEN_WIDTH
    res = ""
    entries.collect! do |line|
        l, r = line.split("|||")
        r ? l.alignr(r.scrunch(width / 4),width) : l
    end
    cmdline = "dmenu -p \"#{prompt}\" -nf #{$FG_COLOR} \
    -nb #{$BG_COLOR} \
    -sb #{$SEL_BG_COLOR} \
    -sf #{$SEL_FG_COLOR} \
    -i -l #{height} \
    -w #{width} \
    -fn #{$FONT}"
    IO.popen(cmdline, "w+") do |io|
        io.print(entries.join("\n"))
        io.close_write
        res = io.gets
    end
    res.to_s.chomp
end

# list of rdf triples
def collect (trips)
    hsh = Hash.new
    trips.each do |this|
        id = this[0]
        pred = this[1]
        val = this[2]
        #puts id, pred, val
        if hsh[id].nil?
            hsh[id] = Hash.new
        end
        hsh[id].store(pred, val)
    end
    hsh
end

def to_db (trips)
    # using a structure like I used for tagfs
    # file cabinet
    #    tag drawers:
    #       files indexed by name
    # instead, for the drawers we have
    # tag name
    #     global ids indexed by tag value
    hsh = Hash.new
    trips.each do |this|
        id = this[0]
        pred = this[1]
        val = this[2]
        #puts id, pred, val
        if hsh[pred].nil?
            hsh[pred] = Hash.new
        end
        if hsh[pred][val].nil?
            hsh[pred][val] = Array.new
        end
        hsh[pred][val] << id
    end
    #print hsh
    hsh
end

$tag_trips =
[
    [:name, :sig, ""],
    [:action, :sig, '"'],
    [:short, :sig, '.']
]

# actions (Proc objects) associated with each class
$class_actions = 
{
    :send_mail => Proc.new { |q|
        email = TMail::Mail.new
        email[to] = my_dmenu([], "TO: ")
        email[subject] = my_dmenu([], "SUB: ")
        #open editor
        ed = ENV['EDITOR'] ? ENV['EDITOR'] : "vim"
        tmpfile = `mktemp`
        `#{ed} #{tmpfile}`
        email[body] = IO.read(tmpfile)
        Net::STMP.start('mail.cs.utexas.edu', 25, nil, "markw", "hacktxmail") do |smtp|
            smtp.send_message email.to_s, "markw@cs.utexas.edu", "miraiwarren@gmail.com"
        end
    }
}


$db = to_db($triples)
$subjects = collect($triples)

#collect($triples).each{|h| puts h}
#$tags = collect($tag_trips)

# our ds needs to have put everything together, tag some subsets,
# and not have those subsets appear there...

def qstr_to_query (qstr)
    name, *items = qstr.split(" ")
    prefixes = items.map{|i| [i[0],i[1..-1]] }
    sig_map = Hash.new
    $tag_trips.each do |trip|
        sig_map[trip[2]] = trip[0]
    end
    keys = Hash.new
    keys[:name] = name
    prefixes.each{|s| keys[sig_map[s[0]]] = s[1]}
    keys
end

# query is a hash of values to match
# fields is a list of fields to return
# if fields is empty, we return all fields
def query(db, query, *fields)
    # this is going to be a list of ids
    result = nil 
    # return a global id 
    # really nasty. linear time for the length of the $triples list
    query.each do |key|
        # drawer_lookup
        myh = db[key[0]][key[1].to_sym]
        result = result.nil? ? myh : result & myh
        #print result
        if result.length <= 1
            break
        end
    end
    result.map{|i| $subjects[i].select{|t| fields.empty? or fields.include?(t)}}
end
def save_db
    # this is pretty lame, but we store the triples as ruby
    # the in-memory triples are put back in data.rb
    data_file = File.open("data.rb", "w")
    data_file.write("$triples = #{$triples.to_s}\n")
    data_file.write("$top_id = #{$top_id}\n")
    data_file.close
end

def delete (db, subj)
    $subjects.delete( subj )
end

def to_triples (db)
    result = []
    $subjects.map do |kv|
        kv[1].map do |tags|
            result << [kv[0], tags[0], tags[1]]
        end
    end
end

$items = query($db, {:Type => :item}, :name, :action, :short)
print $items.to_s

def to_menu(items)
    # looks for an array of hashes
    items.map do |ihash|
        # sort name first and the rest lex by sig
        items = ihash.sort{|a, b|  (a[0] == :name)?-1:a[1] <=> b[1] }
        r = items.map do |a|
            #print "this thing: ", a.to_s, "\n"
            tag_prefix = $subjects[a[0]][:sig].to_s
            value = a[1].to_s
            tag_prefix + value
        end
        r.join(" ")
    end
end
def add_triple(s, p, o)
    $triples << [s, p, o]
end

def newid
    $top_id += 1
    "i#{$top_id}".to_sym
end

def add_action (name, &block)
    add_triple(name.to_sym, :Type, :action)
    add_triple(name.to_sym, :proc, block)
end

def add_entry (name, tags={})
    id = newid
    add_triple(id, :name, name.to_sym)
    add_triple(id, :Type, :item)
    tags.each do |kv|
        add_triple(id, kv[0], kv[1])
    end
end
def add_file (file_name, file_type)
    #file_type is something like "video" or "image"
    #
    if File.exists?(file_name)
        id = newid
        basename = File.basename(file_name)
        absname = File.expand_path(file_name)
        add_triple(id, :name, basename)
        add_triple(id, :file_name, absname)
        add_triple(id, :type, :item)
        # TODO: switch this out with the magic file type
        add_triple(id, :file_type, :file)
    end
end

result = my_dmenu(to_menu($items))
q = qstr_to_query(result)
q[:Type] = :item
qr = query($db, q)
# once we get the item, we execute the action 
print qr
qr.each do |k|
    eval($subjects[k[:action]][:proc]).call(k)
end

save_db
