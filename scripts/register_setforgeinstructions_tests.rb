#!/usr/bin/env ruby
require 'xcodeproj'

project_path = 'Bricky the Brick Scanner.xcodeproj'
project = Xcodeproj::Project.open(project_path)
test_target = project.targets.find { |t| t.name == 'BrickyTests' }
raise 'test target not found' unless test_target

def child_group(parent, name)
  parent.children.find { |c| c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.display_name == name }
end

group = child_group(project.main_group, 'BrickyTests') || project.main_group
filename = 'SetForgeInstructionsTests.swift'
ref = group.files.find { |f| f.display_name == filename } || group.new_reference(filename)
unless test_target.source_build_phase.files_references.include?(ref)
  test_target.add_file_references([ref])
  puts "  + BrickyTests/#{filename}"
else
  puts "  = already registered: #{filename}"
end

project.save
puts 'Saved project.'
