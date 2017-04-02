begin
  require 'plist'
rescue LoadError
  puts 'plist not installed yet!'
end

APP_NAME = 'MyWeight'
ARTIFACTS_DEFAULT_PATH = "#{BASE_PATH}/build"
TEST_REPORTS_DEFAULT_PATH = "#{BASE_PATH}/reports"
WORKSPACE_PATH = "#{BASE_PATH}/#{APP_NAME}.xcworkspace"


# -- danger

desc 'Run danger'
task :danger do
  sh 'bundle exec danger'
end

# -- Tests

desc 'Run unit tests'
task :unit_tests do
  xcode( scheme: 'MyWeight',
         actions: 'clean analyze test',
         destination: 'platform=iOS Simulator,OS=10.3,name=iPhone SE',
         report_name: 'unit-tests' )
end

task :clean_artifacts do
  sh "rm -rf '#{artifacts_path()}' '#{reports_path()}'"
end

task :generate_xcode_summary, [ :output_path ] do |t, args|
  build_file = args[ :output_path ]
  sh "cat #{xcode_log_file(report_name: 'unit-tests')} | XCPRETTY_JSON_FILE_OUTPUT=#{build_file} xcpretty -f `xcpretty-json-formatter`"
end

def artifacts_path
  artifacts_path = ENV["ARTIFACTS_PATH"] || ARTIFACTS_DEFAULT_PATH
  File.expand_path artifacts_path
  FileUtils.mkdir_p artifacts_path

  artifacts_path
end

def reports_path
  reports_path = ENV["TEST_REPORTS_PATH"] || TEST_REPORTS_DEFAULT_PATH
  File.expand_path reports_path
  FileUtils.mkdir_p reports_path

  reports_path
end

def xcode_log_file( report_name: '', artifacts_path: artifacts_path())
  "#{artifacts_path}/xcode-#{report_name}.log"
end

# -- Release

desc 'Release'
task :release => [ :archive, :generate_ipa ]

task :archive do
  xcode( scheme: 'MyWeight',
         actions: 'clean archive',
         destination: 'generic/platform=iOS',
         configuration: 'Release',
         report_name: "archive",
         archive_path: archive_path )
end

task :generate_ipa do
  
  export_plist_path = create_export_plist()
  
  export_ipa( archive_path: archive_path,
              export_path: export_path,
              build_plist: export_plist_path, 
              report_name: "export" )
end

task :upload do
  sh "bundle exec pilot upload --verbose --skip_waiting_for_build_processing true --skip_submission true --wait_processing_interval 1 -i '#{ipa_file_path}' -a '#{bundle_id}'"
end

def archive_path
  "#{artifacts_path()}/#{APP_NAME}.xcarchive"
end

def export_path
  "#{artifacts_path()}/#{APP_NAME}-ipa"  
end

def ipa_file_path
  files = Dir[File.join(export_path, '*.ipa')]
  fail "No IPA found in #{export_path}" if files.to_s.strip.length == 0
  files.last
end

# -- build

def xcode( scheme: '',
           actions: '',
           destination: '',
           configuration: '',
           report_name: '',
           archive_path: '',
           reports_path: reports_path(),
           artifacts_path: artifacts_path()
          )
  xcode_log_file = xcode_log_file(report_name: report_name, artifacts_path: artifacts_path)
  report_file = "#{reports_path}/#{report_name}.xml"

  xcode_configuration = "-configuration '#{configuration}'" unless configuration.to_s.strip.length == 0
  other_options = 'CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= PROVISIONING_PROFILE=' unless actions.include? 'archive'
  archiveOptions = archive_path.to_s.strip.length == 0 ? '-enableCodeCoverage YES' : "-archivePath '#{archive_path}'"

  sh "rm -f '#{xcode_log_file}' '#{report_file}'"
  sh "set -o pipefail && xcodebuild #{other_options} #{xcode_configuration} -destination '#{destination}' -workspace '#{WORKSPACE_PATH}' -scheme '#{scheme}' #{archiveOptions} #{actions} | tee '#{xcode_log_file}' | xcpretty --color --no-utf -r junit -o '#{report_file}'"
end

def export_ipa( archive_path: '',
                export_path: '',
                build_plist: '',
                report_name: '',
                reports_path: reports_path(),
                artifacts_path: artifacts_path()
               )
  xcode_log_file = "#{artifacts_path}/xcode-#{report_name}.log"
  report_file = "#{reports_path}/#{report_name}.xml"

  sh "set -o pipefail && xcodebuild -exportArchive -archivePath '#{archive_path}' -exportPath '#{export_path}' -exportOptionsPlist '#{build_plist}' | tee '#{xcode_log_file}' | xcpretty --color --no-utf -r junit -o '#{report_file}'"
end

def create_export_plist( plist_directory: artifacts_path() )
  plist = {:method => 'app-store'}
  plist_path = "#{plist_directory}/export.plist"
  plist.save_plist plist_path
  plist_path
end