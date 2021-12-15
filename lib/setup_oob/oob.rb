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

require 'logger'
require 'socket'
require 'mixlib/shellout'
require_relative 'command/smc'
require_relative 'command/drac'

# A simple class to do the magic to build the right classes and call the
# right methods.
class OOB
  def initialize(config)
    @host = config[:host] || 'localhost'
    @user = config[:user] || user
    @password = config[:password]
    @level = config[:level]
    @desired_hostname = config[:desired_hn] || build_hostname
    logger.debug("Desired hostname set to #{@desired_hostname}")
    @network_mode = config[:network_mode]
    @network_src = config[:network_src]
    @key = config[:key]
    @type = config[:type]
  end

  def logger
    @logger ||= begin
      logger = Logger.new($stdout)
      logger.level = @level
      logger
    end
  end

  def user
    'ADMIN'
  end

  def converged?
    do_work
  end

  def converge!
    do_work(true)
  end

  private

  def do_work(converge = false)
    # Mmmmm, metaprogramming.
    todo = {
      # password MUST come first
      'password' => @password,
      'hostname' => @desired_hostname,
      'ntp' => ['0.pool.ntp.org', '1.pool.ntp.org'],
      'networkmode' => @network_mode,
      'networksrc' => @network_src,
      'ddns' => nil,
    }

    if @type == 'smc'
      if @key
        todo['license'] = @key
      else
        logger.warn('Will not check/activate license, no private key available')
      end
    end

    unless @password
      logger.warn('Will not check/set admin password, no password specified')
      todo.delete('password')
    end

    unless @network_src
      logger.warn('Will not set network_src, not specified')
      todo.delete('networksrc')
    end

    unless @network_mode
      logger.warn('Will not set network_mode, not specified')
      todo.delete('networkmode')
    end

    ret = true
    optionally_supported = ['ntp', 'ddns']
    cmd = Kernel.const_get("#{@type.upcase}Commands")
    todo.each do |name, arg|
      cls = cmd.const_get(name.capitalize)
      obj = cls.new(@host, logger, arg)
      begin
        if converge
          obj.converge!
        else
          ret &= obj.converged?
        end
      rescue Mixlib::ShellOut::ShellCommandFailed => e
        if optionally_supported.include?(name) &&
           e.message.include?('Invalid data field in request')
          logger.warn("Host does not seem to support #{name}, skipping")
          next
        end
        raise
      end
    end

    unless converge
      return ret
    end
  end

  def build_hostname
    if @host == 'localhost'
      "#{Socket.gethostname.split('.').first}-oob"
    else
      @host
    end
  end
end
