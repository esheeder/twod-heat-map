# Uncomment the next line to define a global platform for your project
platform :ios, '15.0'

target 'twod-heat-map' do
  # Comment the next line if you don't want to use dynamic frameworks
  use_frameworks!

  # Pods for nearwaveBeta
  pod 'Charts'
  pod 'LFHeatMap'
  pod 'SMHeatMapView'
end

post_install do |installer|
        installer.pods_project.targets.each do |target|
            target.build_configurations.each do |config|
                config.build_settings['SWIFT_VERSION'] = '5.0'
            end
        end
    end
