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

require 'ipaddress'

# Mixins for the stuff that's common to a given command regardless
# of the platform
module CommandMixins
  module Hostname
    def _converged?
      hn = hostname
      logger.debug("'#{hn}' vs '#{desired_hostname}'")
      hn == desired_hostname
    end

    def _converge!
      unless _converged?
        logger.info(" - Setting hostname (#{desired_hostname})")
        set_hostname
      end
    end

    def desired_hostname
      @data
    end
  end

  module Ntp
    def _converged?
      servers_correct = true
      servers.each_with_index do |server, idx|
        res = get_server(idx) == server
        logger.debug(" - NTP#{idx + 1} correct: #{res}")
        servers_correct &&= res
      end
      enabled? && servers_correct
    end

    def _converge!
      logger.debug(' - Checking if enabled')
      unless enabled?
        logger.info(' - Enabling NTP')
        enable
      end
      servers.each_with_index do |server, idx|
        logger.debug(" - Checking if NTP#{idx + 1} is correct")
        unless get_server(idx) == server
          logger.info(" - Setting NTP#{idx + 1} server")
          set_server(idx)
        end
      end
    end

    def servers
      @data
    end
  end

  module Networkmode
    def _converged?
      mode_correct?
    end

    def desired_mode
      @data
    end

    def _converge!
      unless mode_correct?
        logger.info(" - Setting network to #{desired_mode}")
        set_mode
      end
    end
  end

  module Ddns
    def _converged?
      enabled?
    end

    def _converge!
      unless enabled?
        logger.info(' - Enabling DDNS')
        enable
      end
    end
  end

  module Networksrc
    def desired_mode
      @data == 'dhcp' ? 'dhcp' : 'static'
    end

    def desired_address
      if @data == 'dhcp'
        fail 'Set to DHCP, but looking for address, what?'
      end

      IPAddress(@data).address
    end

    def desired_netmask
      if @data == 'dhcp'
        fail 'Set to DHCP, but looking for address, what?'
      end

      IPAddress(@data).netmask
    end

    def mode
      x = current['IP Address Source']
      case x
      when /DHCP/
        'dhcp'
      when /Static/
        'static'
      else
        'other'
      end
    end

    def address
      current['IP Address']
    end

    def netmask
      current['Subnet Mask']
    end

    def current
      return @current if @current

      @current = {}
      cmd = ipmicmd + ['lan', 'print', '1']
      s = run(cmd)
      s.stdout.each_line do |line|
        key, val = line.chomp.split(':')
        @current[key.strip] = val.strip
      end
      @current
    end

    def _converged?
      mode? && address?
    end

    def address?
      if desired_mode == 'static'
        logger.debug('  - Checking of address is set')
        logger.debug("'#{@data}' vs '#{@data}'")
        return address == desired_address || netmask == desired_netmask
      end
      true
    end

    def mode?
      logger.debug("  - Checking if network src mode set to #{desired_mode}")
      mode == desired_mode
    end

    def _converge!
      unless mode?
        logger.info(" - Setting network src to #{desired_mode}")
        set_mode
      end
      if desired_mode == 'static'
        logger.info(' - Checking address')
        if address != desired_address
          logger.info(" - Setting network address to #{desired_address}")
          set_address
        end
        if netmask != desired_netmask
          logger.info(" - Setting network mask to #{desired_netmask}")
          set_netmask
        end
      end
    end

    def smc?
      @smc ||= self.class.to_s.start_with?('SMC')
    end

    def set_mode
      cmd = ipmicmd(true) + ['lan', 'set', '1', 'ipsrc', desired_mode]
      run(cmd)
    end

    def set_address
      cmd = ipmicmd(true) + ['lan', 'set', '1', 'ipaddr', desired_address]
      run(cmd)
    end

    def set_netmask
      cmd = ipmicmd(true) + ['lan', 'set', '1', 'netmask', desired_netmask]
      run(cmd)
    end

    def ipmicmd(set = false)
      smc? ? basecmd(set) : SMCCommandBase.basecmd('localhost')
    end
  end

  module Password
    def password
      @data
    end

    def _converged?
      password_set?
    end

    def _converge!
      unless password_set?
        logger.info(' - Setting password')
        set_password
      end
    end

    def smc?
      @smc ||= self.class.to_s.start_with?('SMC')
    end

    # It turns out that 'ipmitool user test' and 'ipmitool user set'
    # work fairly unversally. And there's no way to do 'user test'
    # in racadm. So this should work pretty much everywhere.
    #
    # Though... 'ipmitool user list', for some reason, is not so
    # universal. Womp Womp.
    def password_set?
      id = admin_id
      cmd = ipmicmd + ['user', 'test', id, smc? ? '20' : '16', password]
      s = run(cmd, false)
      !s.error?
    end

    def set_password
      id = admin_id
      cmd = ipmicmd(true) + ['user', 'set', 'password', id, password]
      s = run(cmd)
      if s.error?
        # if the password isn't what we expect *and* isn't ADMIN, it may be
        # serial or an old password. We can reset it to ADMIN
        # NOTE: this actually resets ALL it's settings. Which is OK because
        # we set password first, so the rest will get set properly
        run(ipmicmd(true) + ['raw', '0x30', '0x48', '0x1'])
        # takes about  seconds for it to come to its senses
        sleep(5)
        # now, try again
        run(cmd)
      end
    end

    def ipmicmd(set = false)
      smc? ? basecmd(set) : SMCCommandBase.basecmd('localhost')
    end
  end
end
