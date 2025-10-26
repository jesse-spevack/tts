# frozen_string_literal: true

require "rake/testtask"
require "rubocop/rake_task"

# Default task runs both tests and linting
task default: %i[test rubocop]

# Test task
Rake::TestTask.new(:test) do |t|
  t.libs << "lib"
  t.libs << "test"
  t.test_files = FileList["test/test_*.rb"]
  t.verbose = true
end

# RuboCop task
RuboCop::RakeTask.new(:rubocop) do |t|
  t.options = ["--display-cop-names"]
end

# Run RuboCop with auto-correct
RuboCop::RakeTask.new("rubocop:autocorrect") do |t|
  t.options = ["--autocorrect"]
end

desc "Run tests and linting"
task :ci do
  puts "=" * 60
  puts "Running Tests"
  puts "=" * 60
  Rake::Task["test"].invoke

  puts "\n"
  puts "=" * 60
  puts "Running RuboCop"
  puts "=" * 60
  Rake::Task["rubocop"].invoke
end
