#!/usr/bin/env ruby
# Fuegt alle .h/.m-Dateien aus dem Ordner BVGNearby/, die noch nicht im Xcode-Projekt sind,
# automatisch hinzu (.m auch ins Target). Einmalig noetig: sudo gem install xcodeproj
# Aufruf im Projektordner (neben BVGNearby.xcodeproj): ruby BVGNearby/add_files.rb
require "xcodeproj"

project = Xcodeproj::Project.open("BVGNearby.xcodeproj")
target  = project.targets.find { |t| t.name == "BVGNearby" } || project.targets.first
group   = project.main_group["BVGNearby"]
known   = project.files.map { |f| File.basename(f.path.to_s) }

added = []
Dir.glob("BVGNearby/*.{h,m}").sort.each do |path|
  name = File.basename(path)
  next if known.include?(name)
  ref = group.new_file(name)
  target.add_file_references([ref]) if name.end_with?(".m")
  added << name
end

project.save
puts added.empty? ? "Alles schon im Projekt." : "Hinzugefügt: #{added.join(', ')}"
