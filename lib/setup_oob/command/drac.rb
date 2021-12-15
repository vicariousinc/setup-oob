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

require 'mixlib/shellout'
require_relative 'base'
require_relative 'mixins'

# A slight extension of the Command class to add some DRAC-specific
# utility functions. Will be the base class for all DRAC commands
class DRACCommandBase < CommandBase
  def getval(key)
    s = run(basecmd + ['get', key])
    s.stdout.lines[1].strip.split('=')[1]
  end

  def setval(key, val)
    run(basecmd + ['set', key, val])
  end

  def getvals(key)
    s = run(basecmd + ['get', key])
    data = {}
    s.stdout.each_line do |line|
      next if line.start_with?('[')
      next if line.strip.empty?

      k, v = line.strip.split('=')
      data[k] = v
    end
    data
  end

  def basecmd(_defaultpass = false)
    if @host == 'localhost'
      ['racadm']
    else
      fail NotImplementedError
    end
  end
end

# The collection of all DRAC command classes
class DRACCommands
  # Manage the hostname
  class Hostname < DRACCommandBase
    private

    include CommandMixins::Hostname

    def hostname
      getval('iDRAC.NIC.DnsRacName')
      # data = getvals('iDRAC.NIC')
      # "#{data['DNSRacName']}.#{data['DNSDomainName']}"
    end

    def set_hostname
      setval('iDRAC.NIC.DNSRacName', desired_hostname)
      # setval('iDRAC.NIC.DNSDomainName', dn)
    end
  end

  # Manage NTP
  class Ntp < DRACCommandBase
    private

    include CommandMixins::Ntp

    def vals
      @vals ||= getvals('idrac.NTPConfigGroup')
    end

    # Like the super-class, except we have to save the magic bytes...
    def enabled?
      vals['NTPEnable'] == 'Enabled'
    end

    def enable
      setval('idrac.NTPConfigGroup.NTPEnable', 'Enabled')
    end

    def get_server(idx)
      vals["NTP#{idx + 1}"]
    end

    def set_server(idx)
      setval("idrac.NTPConfigGroup.NTP#{idx + 1}", servers[idx])
    end
  end

  class Ddns < DRACCommandBase
    private

    include CommandMixins::Ddns

    def enabled?
      getval('iDRAC.NIC.DNSRegister') == 'Enabled'
    end

    def enable
      setval('iDRAC.NIC.DNSRegister', 'Enabled')
    end
  end

  class Networksrc < DRACCommandBase
    include CommandMixins::Networksrc
  end

  class Networkmode < DRACCommandBase
    private

    include CommandMixins::Networkmode

    def mode_correct?
      logger.debug('  - Checking NIC mode')
      getval('iDRAC.NIC.Selection').downcase == desired_mode
    end

    def set_mode
      case desired_mode
      when 'shared'
        setval('iDRAC.NIC.Selection', 'LOM1')
      when 'dedicated'
        setval('iDRAC.NIC.Selection', desired_mode.capitalize)
      else
        fail "Unknown NIC mode: #{desired_mode}"
      end
    end
  end

  class Password < DRACCommandBase
    private

    include CommandMixins::Password

    def admin_id
      return @admin_id if @admin_id

      s = run(basecmd + ['get', 'iDrac.Users'])
      s.stdout.each_line do |line|
        next unless line.start_with?('iDRAC.Users')

        key = line.split[0]
        info = getvals(key)
        if info['UserName'] == 'root'
          @admin_id = key.split('.')[2]
          return @admin_id
        end
      end
    end
  end
end
