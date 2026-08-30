#!/usr/bin/env ruby
require 'xcodeproj'

project_path = 'Bricky the Brick Scanner.xcodeproj'
project = Xcodeproj::Project.open(project_path)
app_target = project.targets.find { |t| t.name == 'Bricky' }
raise 'app target not found' unless app_target

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

group = group_at(project, ['Bricky', 'Resources'])
filename = 'setmodel_fll.mpd'
ref = group.files.find { |f| f.display_name == filename } || group.new_reference(filename)
unless app_target.resources_build_phase.files_references.include?(ref)
  app_target.add_resources([ref])
  puts "  + Resources/#{filename}"
else
  puts "  = already registered: #{filename}"
end

project.save
puts 'Saved project.'
