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

require 'openssl'
require_relative 'base'
require_relative 'mixins'

# A slight extension of the Command class to add some SMC-specific
# utility functions. Will be the base class for all SMC commands
class SMCCommandBase < CommandBase
  DEFAULT_PASSWORD = 'ADMIN'.freeze
  USER = 'ADMIN'.freeze
  COMMANDS = {
    :hostname => [0x47],
    :ntp => [0x68, 0x01],
    :ddns => [0x68, 0x04],
    :networkmode => [0x70, 0x0c],
    :isactivated => [0x6A],
    :setlicense => [0x69],
    # some magic set of bytes for firmware version and mac ...
  }.freeze

  ACTIONS = {
    :get => [0x00],
    :set => [0x01],
  }.freeze

  def enabled?
    # assumes a sub-classed cmdbytes
    data = cmdbytes(:get, :enabled)
    out = runraw(data)
    # if the first byte is 1, "it" is enabled, whatever "it" is
    en = out[0] == 1
    logger.debug("#{pretty_self} enabled: #{en}")
    en
  end

  # Get the IPMI bytes for the command we want to run
  def cmdbytes(command, action = nil)
    data = [0x30] + COMMANDS[command]
    if action
      data += ACTIONS[action]
    end
    data
  end

  # Wrapper to build the "raw" command, run it, and convert the answer into
  # an array of actual integers.
  def runraw(data)
    s = run(rawcmd(data))
    s.stdout.split.map { |x| x.to_i(16) }
  end

  # Builds the 'raw' command using 'data'
  def rawcmd(data)
    basecmd + ['raw'] + data.map(&:to_s)
  end

  def basecmd(defaultpass = false)
    SMCCommandBase.basecmd(@host, @user, defaultpass ? 'ADMIN' : @password)
  end

  def self.basecmd(host, user = nil, pass = nil)
    if host == 'localhost'
      ['ipmitool']
    else
      unless user && pass
        fail 'basecmd: No user and password sent with host'
      end

      [
        'ipmitool',
        '-H', host,
        '-U', user,
        '-P', pass
      ]
    end
  end
end

# The collection of all SMC command classes
class SMCCommands
  class Hostname < SMCCommandBase
    private

    include CommandMixins::Hostname

    def desired_hostname
      @data
    end

    def hostname
      # for hostname get is 0x02 and set is 0x01. no idea why
      data = cmdbytes(:hostname) + [0x02]
      out = runraw(data)
      bytes_to_str(out)
    end

    def set_hostname
      # no terminating null for this command...
      data = cmdbytes(:hostname) + [0x01] + desired_hostname.bytes
      runraw(data)
    end
  end

  class Ntp < SMCCommandBase
    SUB_COMMANDS = {
      :enabled => [0x00],
      :primary => [0x01],
      :secondary => [0x02],
    }.freeze

    TYPES = [
      :primary,
      :secondary,
    ].freeze

    private

    include CommandMixins::Ntp

    def cmdbytes(action, subcmd)
      super(:ntp, action) + SUB_COMMANDS[subcmd]
    end

    def enabled?
      data = cmdbytes(:get, :enabled)
      out = runraw(data)
      en = out[0] == 1
      # when you check if NTP is enabled, a bunch of extra bytes
      # are passed back that MUST be passed in when enabling NTP
      @_magic = out[1..-1]
      logger.debug("NTP enabled: #{en}, magic bytes: #{@_magic}")
      en
    end

    def enable
      # 0x01 is "enable"
      data = cmdbytes(:set, :enabled) + [0x01] + @_magic
      runraw(data)
    end

    def get_server(idx)
      data = cmdbytes(:get, type(idx))
      bytes_to_str(runraw(data))
    end

    def type(idx)
      TYPES[idx]
    end

    def set_server(idx)
      name_bytes = servers[idx].bytes
      data = cmdbytes(:set, type(idx)) + name_bytes + [0x00] # null termination
      bytes_to_str(runraw(data))
    end
  end

  class Networksrc < SMCCommandBase
    include CommandMixins::Networksrc
  end

  class Networkmode < SMCCommandBase
    private

    MODES = {
      :dedicated => 0x00,
      :shared => 0x01,
      :failover => 0x02,
    }.freeze

    include CommandMixins::Networkmode

    def mode_val
      val = MODES[desired_mode.to_sym]
      unless val
        fail "No such mode #{desired_mode}"
      end

      val
    end

    def cmdbytes(action, _subcmd = nil)
      super(:networkmode, action)
    end

    def mode_correct?
      data = cmdbytes(:get)
      out = runraw(data)[0]
      logger.debug("mode: #{out}")
      out == mode_val
    end

    def set_mode
      data = cmdbytes(:set) + [mode_val]
      runraw(data)
    end
  end

  class Ddns < SMCCommandBase
    SUB_COMMANDS = {
      :enabled => [0x00],
    }.freeze

    private

    include CommandMixins::Ddns

    def cmdbytes(action = nil, type = nil)
      # this one is backwards...  I dunno why
      data = super(:ddns)
      if action && type
        data += SUB_COMMANDS[type] + ACTIONS[action]
      end
      data
    end

    def enable
      # this seems to put it in some sort of setting mode...
      data = cmdbytes(:set, :enabled)
      runraw(data)
      data = cmdbytes
      # then you do this crazy magic...
      data += [0x01, 0x01, 0x00, 0x7F, 0x00, 0x00, 0x01] +
        '#host.#domain'.bytes + [0x00]
      runraw(data)
    end
  end

  # Manage the licenses
  #
  # READ CAREFULLY!!
  # Generating licenses if you haven't purchased them is illegal!
  # This is here for convenience since the license is derivable from
  # the MAC address, if you have the keys. This allows activating
  # the license in an automated fashion.
  #
  # I make no claims about the legality of having the key, it probably
  # depends on what country you are in. The key is not distributed with
  # this software. But you can find it if you want.
  #
  class License < SMCCommandBase
    def key
      @data
    end

    def _converged?
      licensed?
    end

    def converge!
      unless licensed?
        logger.info(' - Setting license')
        set_license
      end
    end

    private

    # Thanks Peter Kleissner for documenting this.
    def generate_license
      digest = OpenSSL::Digest.new('sha1')
      data = mac.split(':').map { |x| x.to_i(16).chr }.join
      raw = OpenSSL::HMAC.digest(digest, key, data)
      raw_lic = raw.chars[0..11].map(&:ord)
      fmt = "%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X\n"
      logger.debug("Generated license: #{raw_lic}")
      logger.debug("Human readable license: #{fmt % raw_lic}")
      raw_lic
    end

    def licensed?
      data = cmdbytes(:isactivated)
      s = runraw(data)
      # There's only one byte, and it's non-zero if we're activated
      en = s[0].positive?
      logger.debug("Activated: #{en}")
      en
    end

    def mac
      # does not use `cmdbytes` because this is the raw sequence of
      # bytes and not inside of the "0x30' netfn that other commands
      # are
      data = [0x0C, 0x02, 0x01, 0x05, 0x00, 0x00]
      # we want actual hex strings, so use run directly
      s = run(rawcmd(data))
      hex = s.stdout.split
      # first byte is version, I think
      hex.shift
      mac = hex.join(':')
      logger.debug("Mac is #{mac}")
      mac
    end

    def set_license
      lic = generate_license
      data = cmdbytes(:setlicense) + lic
      s = runraw(data)
      unless s[0].zero?
        fail 'Failed to set license key'
      end
    end
  end

  class Password < SMCCommandBase
    private

    include CommandMixins::Password

    # Find the user id of the ADMIN user. Usually 2, but I
    # didn't want to hard-code that.
    def admin_id
      return @admin_id if @admin_id

      s = run(basecmd + ['user', 'list'])
      s.stdout.each_line do |line|
        next if line.start_with?('ID')

        bits = line.split
        if bits[1] == 'ADMIN'
          @admin_id = bits[0]
          return @admin_id
        end
      end
    end
  end
end
