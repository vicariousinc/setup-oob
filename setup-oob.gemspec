# Copyright 2013-present Vicarious
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

require_relative './lib/setup_oob/version'

Gem::Specification.new do |s|
  s.name = 'setup_oob'
  s.version = SetupOOB::VERSION
  s.summary = 'Setup OOB systems from Linux'
  s.description = 'Utility for configuring OOB devices from linux'
  s.license = 'Apache-2.0'
  s.authors = ['Phil Dibowitz']
  s.homepage = 'https://github.com/vicariousinc/setup-oob'
  s.platform = Gem::Platform::RUBY
  s.extra_rdoc_files = %w{README.md LICENSE CHANGELOG.md}
  s.required_ruby_version = '>= 2.5.0'

  s.bindir = %w{bin}
  s.executables = %w{setup-oob}
  s.files = %w{README.md LICENSE} +
    Dir.glob('{lib}/**/*', File::FNM_DOTMATCH).
            reject { |f| File.directory?(f) }
end
