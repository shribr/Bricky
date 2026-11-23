#!/usr/bin/env ruby
require 'xcodeproj'

project_path = 'Bricky the Brick Scanner.xcodeproj'
project = Xcodeproj::Project.open(project_path)

app_target  = project.targets.find { |t| t.name == 'Bricky' }
test_target = project.targets.find { |t| t.name == 'BrickyTests' }
raise 'app target not found'  unless app_target
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

def add_file(project, target, group, rel_filename)
  existing = group.files.find { |f| f.display_name == rel_filename }
  ref = existing || group.new_reference(rel_filename)
  unless target.source_build_phase.files_references.include?(ref)
    target.add_file_references([ref])
  end
  puts "  + #{group.display_name}/#{rel_filename}"
end

app_files = {
  ['Bricky', 'Services', 'Printing'] => ['STLScaler.swift'],
  ['Bricky', 'ViewModels']           => ['SendToPrinterViewModel.swift'],
  ['Bricky', 'Views', 'Printing']    => ['SendToPrinterView.swift'],
}

test_files = {
  ['BrickyTests'] => ['STLScalerTests.swift', 'SendToPrinterViewModelTests.swift'],
}

puts 'App target:'
app_files.each do |path, files|
  grp = group_at(project, path)
  files.each { |f| add_file(project, app_target, grp, f) }
end

puts 'Test target:'
test_files.each do |path, files|
  grp = group_at(project, path)
  files.each { |f| add_file(project, test_target, grp, f) }
end

project.save
puts 'Saved project.'
