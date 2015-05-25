module Gersberms
  module Errors
    class CommandFailedError < RuntimeError
      attr_reader :stdout, :stderr, :exit_status, :exit_signal
      def initialize(stdout, stderr, exit_status, exit_signal)
        @stdout = stdout
        @stderr = stderr
        @exitstatus = exit_status
        @exit_signal = exit_signal
      end
    end
  end
end
