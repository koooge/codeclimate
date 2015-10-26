require "spec_helper"
require "file_utils_ext"

module CC::Analyzer
  describe EnginesBuilder do
    include FileSystemHelpers

    let(:engines_builder) do
      EnginesBuilder.new(
        registry: registry,
        config: config,
        container_label: container_label,
        source_dir: source_dir,
        requested_paths: requested_paths
      )
    end
    let(:container_label) { nil }
    let(:requested_paths) { [] }
    let(:source_dir) { "/code" }

    around do |test|
      within_temp_dir { test.call }
    end

    before do
      system("git init > /dev/null")
    end

    describe "with one engine" do
      let(:config) { config_with_engine("an_engine") }
      let(:registry) { registry_with_engine("an_engine") }

      before do
        FileUtils.stubs(:readable_by_all?).at_least_once.returns(true)
      end

      it "contains that engine" do
        engines = engines_builder.run
        engines.size.must_equal(1)
        engines.first.name.must_equal("an_engine")
      end
    end

    describe "with an invalid engine name" do
      let(:config) { config_with_engine("an_engine") }
      let(:registry) { {} }

      it "does not raise" do
        engines_builder.run
      end
    end

    describe "with engine-specific config" do
      let(:config) do
        CC::Yaml.parse <<-EOYAML
          engines:
            rubocop:
              enabled: true
              config:
                file: rubocop.yml
        EOYAML
      end
      let(:registry) { registry_with_engine("rubocop") }

      before do
        FileUtils.stubs(:readable_by_all?).at_least_once.returns(true)
      end

      it "keeps that config and adds some entries" do
        expected_config = {
          "enabled" => true,
          "config" => "rubocop.yml",
          :exclude_paths => [],
          :include_paths => ["./"]
        }
        Engine.expects(:new).with(
          "rubocop",
          registry["rubocop"],
          source_dir,
          expected_config,
          anything
        )
        engines_builder.run
      end
    end

    describe "with a .gitignore file" do
      let(:config) do
        CC::Yaml.parse <<-EOYAML
          engines:
            rubocop:
              enabled: true
        EOYAML
      end
      let(:registry) { registry_with_engine("rubocop") }

      before do
        make_file(".ignorethis")
        make_file(".gitignore", ".ignorethis\n")
      end

      before do
        FileUtils.stubs(:readable_by_all?).at_least_once.returns(true)
      end

      it "respects those paths" do
        expected_config = {
          "enabled" => true,
          :exclude_paths => %w(.ignorethis),
          :include_paths => %w(.gitignore)
        }
        Engine.expects(:new).with(
          "rubocop",
          registry["rubocop"],
          source_dir,
          expected_config,
          anything
        )
        engines_builder.run
      end
    end

    describe "when the source directory contains all readable files, and there are no ignored files" do
      let(:config) { config_with_engine("an_engine") }
      let(:registry) { registry_with_engine("an_engine") }

      before do
        make_file("root_file.rb")
        make_file("subdir/subdir_file.rb")
      end

      it "gets include_paths from IncludePathBuilder" do
        IncludePathsBuilder.stubs(:new).with([], []).returns(mock(build: ['.']))
        expected_config = {
          "enabled" => true,
          :exclude_paths => [],
          :include_paths => ['.']
        }
        Engine.expects(:new).with(
          "an_engine",
          registry["an_engine"],
          source_dir,
          expected_config,
          anything
        )
        engines_builder.run
      end
    end

    describe "with a custom engine class" do
      let(:config) { config_with_engine("engine1", "engine2") }
      let(:registry) { registry_with_engine("engine1", "engine2") }
      let(:engine_class) { stub("MySpecialEngine") }

      before do
        FileUtils.stubs(:readable_by_all?).at_least_once.returns(true)
      end

      it "instantiates that class with the arguments" do
        expected_config = {
          "enabled" => true,
          :exclude_paths => [],
          :include_paths => ["./"]
        }
        engine_instance1 = stub("MySpecialEngine instance 1")
        engine_instance2 = stub("MySpecialEngine instance 2")
        engine_class.expects(:new).with(
          "engine1",
          registry["engine1"],
          source_dir,
          expected_config,
          anything
        ).returns(engine_instance1)
        engine_class.expects(:new).with(
          "engine2",
          registry["engine2"],
          source_dir,
          expected_config,
          anything
        ).returns(engine_instance2)
        result = engines_builder.run(engine_class)
        result.must_equal([engine_instance1, engine_instance2])
      end
    end

    def registry_with_engine(*names)
      {}.tap do |result|
        names.each do |name|
          result[name] = { "image" => "codeclimate/codeclimate-#{name}" }
        end
      end
    end

    def config_with_engine(*names)
      raw = "engines:\n"
      names.each do |name|
        raw << "  #{name}:\n    enabled: true\n"
      end
      CC::Yaml.parse(raw)
    end

    def null_formatter
      formatter = stub(started: nil, write: nil, run: nil, finished: nil, close: nil)
      formatter.stubs(:engine_running).yields
      formatter
    end
  end
end
