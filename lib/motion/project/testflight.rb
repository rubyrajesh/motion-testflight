# Copyright (c) 2012, Laurent Sansonetti <lrz@hipbyte.com>
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 
# 1. Redistributions of source code must retain the above copyright notice,
#    this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

unless defined?(Motion::Project::Config)
  raise "This file must be required within a RubyMotion project Rakefile."
end

class TestFlightConfig
  attr_accessor :sdk, :api_token, :team_token, :distribution_lists

  def initialize(config)
    @config = config
  end

  def sdk=(sdk)
    if @sdk != sdk
      @config.unvendor_project(@sdk)
      @sdk = sdk
      @config.vendor_project(sdk, :static)
      libz = '/usr/lib/libz.dylib'
      @config.libs << libz unless @config.libs.index(libz) 
    end
  end

  def team_token=(team_token)
    @team_token = team_token
    create_launcher
  end

  def inspect
    {:sdk => sdk, :api_token => api_token, :team_token => team_token, :distribution_lists => distribution_lists}.inspect
  end

  private

  def create_launcher
    return unless team_token
    launcher_code = <<EOF
# This file is automatically generated. Do not edit.

if Object.const_defined?('TestFlight') and !UIDevice.currentDevice.model.include?('Simulator')
  NSNotificationCenter.defaultCenter.addObserverForName(UIApplicationDidBecomeActiveNotification, object:nil, queue:nil, usingBlock:lambda do |notification|
  TestFlight.takeOff('#{team_token}')
  end)
end
EOF
    launcher_file = './app/testflight_launcher.rb'
    if !File.exist?(launcher_file) or File.read(launcher_file) != launcher_code
      File.open(launcher_file, 'w') { |io| io.write(launcher_code) }
    end
    files = @config.files
    files << launcher_file unless files.find { |x| File.expand_path(x) == File.expand_path(launcher_file) }
  end
end

module Motion; module Project; class Config
  variable :testflight

  def testflight
    @testflight ||= TestFlightConfig.new(self)
  end
end; end; end

namespace 'testflight' do
  desc "Submit an archive to TestFlight"
  task :submit => 'archive' do
    # Retrieve configuration settings.
    prefs = App.config.testflight
    App.fail "A value for app.testflight.api_token is mandatory" unless prefs.api_token
    App.fail "A value for app.testflight.team_token is mandatory" unless prefs.team_token
    distribution_lists = (prefs.distribution_lists ? prefs.distribution_lists.join(',') : nil)
    notes = ENV['notes']
    App.fail "Submission notes must be provided via the `notes' environment variable. Example: rake testflight notes='w00t'" unless notes
  
    # An archived version of the .dSYM bundle is needed.
    app_dsym = App.config.app_bundle('iPhoneOS').sub(/\.app$/, '.dSYM')
    app_dsym_zip = app_dsym + '.zip'
    if !File.exist?(app_dsym_zip) or File.mtime(app_dsym) > File.mtime(app_dsym_zip)
      Dir.chdir(File.dirname(app_dsym)) do
        sh "/usr/bin/zip -q -r \"#{File.basename(app_dsym)}.zip\" \"#{File.basename(app_dsym)}\""
      end
    end  
  
    curl = "/usr/bin/curl http://testflightapp.com/api/builds.json -F file=@\"#{App.config.archive}\" -F dsym=@\"#{app_dsym_zip}\" -F api_token='#{prefs.api_token}' -F team_token='#{prefs.team_token}' -F notes=\"#{notes}\" -F notify=True"
    curl << " -F distribution_lists='#{distribution_lists}'" if distribution_lists
    App.info 'Run', curl
    sh curl
  end
end

desc 'Same as testflight:submit'
task 'testflight' => 'testflight:submit'
