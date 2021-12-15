# vim: syntax=ruby:expandtab:shiftwidth=2:softtabstop=2:tabstop=2

# Copyright 2021-present Vicarious
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# The base class for a command
class CommandBase
  attr_accessor :logger

  def initialize(host, logger, data)
    @host = host
    @logger = logger
    # data is any extra data subcommands might need
    @data = data
  end

  def converged?
    converged = _converged?
    logger.info("#{pretty_self}: converged: #{converged}")
    converged
  end

  def converge!
    logger.info("Validating #{pretty_self}")
    _converge!
  end

  private

  def _converged?
    fail NotImplementedError
  end

  def _converge!
    fail NotImplementedError
  end

  def pretty_self
    self.class.to_s.split('::').last
  end

  # not applicable to all sub-classes, but common enough might
  # as well include it here.
  def enabled?
    fail NotImplementedError
  end

  # get a single value you from the device
  def getval(_key)
    fail NotImplementedError
  end

  # set key to val
  def setval(_key, _val)
    fail NotImplementedError
  end

  # same as get, but handles multi-value gets and returns a hash
  def getvals(_key)
    fail NotImplementedError
  end

  # Simpler wrapper around Mixlib::ShellOut to log the command
  def run(cmd, forcefail = true)
    logger.debug("Running: #{cmd.join(' ')}")
    s = Mixlib::ShellOut.new(*cmd)
    s.run_command
    s.error! if forcefail
    s
  end

  # Given an array of bytes, get a string out of it.
  def bytes_to_str(bytes)
    bytes.pack('C*').force_encoding('utf-8')
  end

  def basecmd(_defaultpass)
    fail NotImplementedError
  end
end
