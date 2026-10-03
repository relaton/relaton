# The FileIO/Type examples must be hermetic: a developer's real ~/.relaton
# cache (79k-row flavor indexes) would otherwise be read through the paths
# whose urls those specs pass as bare symbols. index_spec asserts the DEFAULT
# config, so only redirect storage for the two suites that read through it —
# and reset both the config and the pooled types afterward, so nothing leaks
# into the other examples in the run.
RSpec.configure do |config|
  config.around(:each) do |example|
    if example.metadata[:file_path].to_s.match?(%r{(type|file_io)_spec\.rb})
      dir = Dir.mktmpdir
      Relaton::Index.instance_variable_set(:@config, nil)
      Relaton::Index.configure { |c| c.storage_dir = dir }
      begin
        example.run
      ensure
        Relaton::Index.instance_variable_set(:@config, nil)
        Relaton::Index.instance_variable_set(:@pool, nil)
        FileUtils.remove_entry(dir)
      end
    else
      example.run
    end
  end
end
