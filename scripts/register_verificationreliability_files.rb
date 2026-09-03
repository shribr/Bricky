#!/usr/bin/env ruby
require 'xcodeproj'

project_path = 'Bricky the Brick Scanner.xcodeproj'
project = Xcodeproj::Project.open(project_path)
app_target = project.targets.find { |t| t.name == 'Bricky' }
test_target = project.targets.find { |t| t.name == 'BrickyTests' }
raise 'app target not found' unless app_target
raise 'test target not found' unless test_target

def child_group(parent, name)
  parent.children.find { |c| c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.display_name == name }
end

def group_at(project, components)
  grp = project.main_group
  components.each do |name|
    nxt = child_group(grp, name)
    nxt ||= grp.new_group(name, name)
    grp = nxt
  end
  grp
end

def add_source(target, group, filename)
  ref = group.files.find { |f| f.display_name == filename } || group.new_reference(filename)
  if target.source_build_phase.files_references.include?(ref)
    puts "  = already registered: #{filename}"
  else
    target.add_file_references([ref])
    puts "  + #{filename}"
  end
end

add_source(app_target, group_at(project, ['Bricky', 'Services']), 'VerificationReliabilityStore.swift')
add_source(test_target, group_at(project, ['BrickyTests']), 'VerificationReliabilityStoreTests.swift')

project.save
puts 'Saved project.'
