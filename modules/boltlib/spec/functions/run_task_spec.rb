require 'spec_helper'
require 'bolt/target'

describe 'run_task' do
  include PuppetlabsSpec::Fixtures
  let(:executor) { mock('bolt_executor') }
  let(:inventory) { mock('inventory') }

  around(:each) do |example|
    Puppet[:tasks] = true
    Puppet.features.stubs(:bolt?).returns(true)
    executor.stubs(:noop).returns(false)

    Puppet.override(bolt_executor: executor, bolt_inventory: inventory) do
      example.run
    end
  end

  context 'it calls bolt executor run_task' do
    let(:hostname) { 'a.b.com' }
    let(:hostname2) { 'x.y.com' }
    let(:message) { 'the message' }
    let(:target) { Bolt::Target.from_uri(hostname) }
    let(:target2) { Bolt::Target.from_uri(hostname2) }
    let(:result) { Bolt::Result.new(target, value: { '_output' => message }) }
    let(:result2) { Bolt::Result.new(target2, value: { '_output' => message }) }
    let(:result_set) { Bolt::ResultSet.new([result]) }
    let(:tasks_root) { File.expand_path(fixtures('modules', 'test', 'tasks')) }
    let(:default_args) { { 'message' => message } }

    it 'when running a task without metadata the input method is "both"' do
      executable = File.join(tasks_root, 'echo.sh')

      executor.expects(:run_task).with([target], executable, 'both', default_args, {}).returns(result_set)
      inventory.expects(:get_targets).with(hostname).returns([target])

      is_expected.to run.with_params('Test::Echo', hostname, default_args).and_return(result_set)
    end

    it 'when running a task with metadata - the input method is specified by the metadata' do
      executable = File.join(tasks_root, 'meta.sh')

      executor.expects(:run_task).with([target], executable, 'environment', default_args, {})
              .returns(result_set)
      inventory.expects(:get_targets).with(hostname).returns([target])

      is_expected.to run.with_params('Test::Meta', hostname, default_args).and_return(result_set)
    end

    it 'when called with _run_as - _run_as is passed to the executor' do
      executable = File.join(tasks_root, 'meta.sh')

      executor.expects(:run_task).with([target], executable, 'environment', default_args, '_run_as' => 'root')
              .returns(result_set)
      inventory.expects(:get_targets).with(hostname).returns([target])

      args = default_args.merge('_run_as' => 'root')
      is_expected.to run.with_params('Test::Meta', hostname, args).and_return(result_set)
    end

    it 'when called without without args hash (for a task where this is allowed)' do
      executable = File.join(tasks_root, 'yes.sh')

      executor.expects(:run_task).with([target], executable, 'both', {}, {}).returns(result_set)
      inventory.expects(:get_targets).with(hostname).returns([target])

      is_expected.to run.with_params('test::yes', hostname).and_return(result_set)
    end

    it 'when called with no destinations - does not invoke bolt' do
      executor.expects(:run_task).never
      inventory.expects(:get_targets).with([]).returns([])

      is_expected.to run.with_params('Test::Yes', []).and_return(Bolt::ResultSet.new([]))
    end

    context 'with multiple destinations' do
      let(:result_set) { Bolt::ResultSet.new([result, result2]) }

      it 'nodes can be specified as repeated nested arrays and strings and combine into one list of nodes' do
        executable = File.join(tasks_root, 'meta.sh')

        executor.expects(:run_task).with([target, target2], executable, 'environment', default_args, {})
                .returns(result_set)
        inventory.expects(:get_targets).with([hostname, [[hostname2]], []]).returns([target, target2])

        is_expected.to run.with_params('Test::Meta', [hostname, [[hostname2]], []], default_args)
                          .and_return(result_set)
      end

      it 'nodes can be specified as repeated nested arrays and Targets and combine into one list of nodes' do
        executable = File.join(tasks_root, 'meta.sh')

        executor.expects(:run_task).with([target, target2], executable, 'environment', default_args, {})
                .returns(result_set)
        inventory.expects(:get_targets).with([target, [[target2]], []]).returns([target, target2])

        is_expected.to run.with_params('Test::Meta', [target, [[target2]], []], default_args)
                          .and_return(result_set)
      end

      context 'when a command fails on one node' do
        let(:failresult) { Bolt::Result.new(target2, error: { 'msg' => 'oops' }) }
        let(:result_set) { Bolt::ResultSet.new([result, failresult]) }

        it 'errors by default' do
          executable = File.join(tasks_root, 'meta.sh')

          executor.expects(:run_task).with([target, target2], executable, 'environment', default_args, {})
                  .returns(result_set)
          inventory.expects(:get_targets).with([hostname, hostname2]).returns([target, target2])

          is_expected.to run.with_params('Test::Meta', [hostname, hostname2], default_args)
                            .and_raise_error(Bolt::RunFailure)
        end

        it 'does not error with _catch_errors' do
          executable = File.join(tasks_root, 'meta.sh')

          executor.expects(:run_task).with([target, target2], executable, 'environment', default_args, {})
                  .returns(result_set)
          inventory.expects(:get_targets).with([hostname, hostname2]).returns([target, target2])

          args = default_args.merge('_catch_errors' => true)
          is_expected.to run.with_params('Test::Meta', [hostname, hostname2], args)
        end
      end
    end

    context 'when called on a module that contains manifests/init.pp' do
      it 'the call does not load init.pp' do
        executor.expects(:run_task).never
        inventory.expects(:get_targets).with([]).returns([])

        is_expected.to run.with_params('test::echo', [])
      end
    end

    context 'when called on a module that contains tasks/init.sh' do
      it 'finds task named after the module' do
        executable = File.join(tasks_root, 'init.sh')

        executor.expects(:run_task).with([target], executable, 'both', {}, {}).returns(result_set)
        inventory.expects(:get_targets).with(hostname).returns([target])

        is_expected.to run.with_params('test', hostname).and_return(result_set)
      end
    end

    it 'when called with non existing task - reports an unknown task error' do
      is_expected.to run.with_params('test::nonesuch', []).and_raise_error(/Task not found: test::nonesuch/)
    end
  end

  context 'it validates the task parameters' do
    let(:task_name) { 'Test::Params' }
    let(:hostname) { 'a.b.com' }
    let(:task_params) { {} }

    it 'errors when unknown parameters are specified' do
      task_params.merge!(
        'foo' => nil,
        'bar' => nil
      )

      is_expected.to run.with_params(task_name, hostname, task_params).and_raise_error(
        Puppet::ParseError,
        /Task\ test::params:\n
         \s*has\ no\ parameter\ named\ 'foo'\n
         \s*has\ no\ parameter\ named\ 'bar'/x
      )
    end

    it 'errors when required parameters are not specified' do
      task_params['mandatory_string'] = 'str'

      is_expected.to run.with_params(task_name, hostname, task_params).and_raise_error(
        Puppet::ParseError,
        /Task\ test::params:\n
         \s*expects\ a\ value\ for\ parameter\ 'mandatory_integer'\n
         \s*expects\ a\ value\ for\ parameter\ 'mandatory_boolean'/x
      )
    end

    it "errors when the specified parameter values don't match the expected data types" do
      task_params.merge!(
        'mandatory_string'  => 'str',
        'mandatory_integer' => 10,
        'mandatory_boolean' => 'str',
        'optional_string'   => 10
      )

      is_expected.to run.with_params(task_name, hostname, task_params).and_raise_error(
        Puppet::ParseError,
        /Task\ test::params:\n
         \s*parameter\ 'mandatory_boolean'\ expects\ a\ Boolean\ value,\ got\ String\n
         \s*parameter\ 'optional_string'\ expects\ a\ value\ of\ type\ Undef\ or\ String,
                                        \ got\ Integer/x
      )
    end

    it 'errors when the specified parameter values are outside of the expected ranges' do
      task_params.merge!(
        'mandatory_string'  => '0123456789a',
        'mandatory_integer' => 10,
        'mandatory_boolean' => true,
        'optional_integer'  => 10
      )

      is_expected.to run.with_params(task_name, hostname, task_params).and_raise_error(
        Puppet::ParseError,
        /Task\ test::params:\n
         \s*parameter\ 'mandatory_string'\ expects\ a\ String\[1,\ 10\]\ value,\ got\ String\n
         \s*parameter\ 'optional_integer'\ expects\ a\ value\ of\ type\ Undef\ or\ Integer\[-5,\ 5\],
                                         \ got\ Integer\[10,\ 10\]/x
      )
    end

    it "errors when a specified parameter value is not Data" do
      task_params.merge!(
        'mandatory_string'  => 'str',
        'mandatory_integer' => 10,
        'mandatory_boolean' => true,
        'optional_hash'     => { now: Time.now }
      )

      is_expected.to run.with_params(task_name, hostname, task_params).and_raise_error(
        Puppet::ParseError, /Task parameters is not of type Data/
      )
    end
  end
end
