#--
# Copyright 2014 Red Hat, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#++

require 'openshift-origin-node/model/watchman/watchman_plugin'

# Provide OpenShift with garbage collection for Frontend Proxy configurations
# @!attribute [r] next_check
#   @return [DateTime] timestamp for next check
class FrontendPlugin < OpenShift::Runtime::WatchmanPlugin
  attr_reader :next_check

  # @param [see OpenShift::Runtime::WatchmanPlugin#initialize] config
  # @param [see OpenShift::Runtime::WatchmanPlugin#initialize] logger
  # @param [see OpenShift::Runtime::WatchmanPlugin#initialize] gears
  # @param [see OpenShift::Runtime::WatchmanPlugin#initialize] operation
  # @param [lambda<>] next_update calculates the time for next check
  # @param [DateTime] epoch is when plugin was object instantiated
  def initialize(config, logger, gears, operation, next_update = nil, epoch = DateTime.now)
    super(config, logger, gears, operation)

    @deleted_age = 172800
    @deleted_age = ENV['FRONTEND_CLEANUP_PERIOD'].to_i unless ENV['FRONTEND_CLEANUP_PERIOD'].nil?

    @next_update = next_update || lambda { DateTime.now + Rational(@deleted_age, 86400) }
    @next_check  = epoch
  end

  # Test gears' environment for OPENSHIFT_GEAR_DNS existing
  # @param [OpenShift::Runtime::WatchmanPluginTemplate::Iteration] iteration not used
  # @return void
  def apply(iteration)
    return if DateTime.now < @next_check
    @next_check = @next_update.call

    reload_needed = false

    conf_dir = @config.get('OPENSHIFT_HTTP_CONF_DIR', '/etc/httpd/conf.d/openshift')
    Dir.glob(PathUtils.join(conf_dir, '*.conf')).each do |conf_file|
      next if File.size?(conf_file)
      next if File.mtime(conf_file) > (DateTime.now - Rational(1, 24))

      @logger.info %Q(watchman frontend plugin cleaned up #{conf_file})
      File.delete(conf_file)
      gear_dir = conf_file.gsub('_0_', '_')
      gear_dir = gear_dir.gsub('.conf', '')

      FileUtils.rm_r(gear_dir)
      reload_needed = true
    end

    if reload_needed
      ::OpenShift::Runtime::Frontend::Http::Plugins::reload_httpd
    end
  end
end
