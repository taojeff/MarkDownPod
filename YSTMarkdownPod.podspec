Pod::Spec.new do |s|
  s.name             = 'YSTMarkdownPod'
  s.version          = '0.1.1.2'
  s.summary          = 'A powerful and versatile Markdown rendering library for Swift developers'
  s.description      = <<-DESC
                       GMarkdown is a powerful and versatile Markdown rendering library designed for Swift developers. 
                       Built on top of the swift-markdown parser, GMarkdown offers pure native rendering capabilities, 
                       ensuring seamless integration and high performance for your iOS applications.
                       
                       Features:
                       - Pure Native Rendering
                       - Rich Text Support  
                       - Image Rendering
                       - Code Blocks with syntax highlighting
                       - Tables
                       - LaTeX Math Formulas
                       - Mermaid Diagrams
                       - HTML Preview
                       DESC

  s.homepage         = 'https://github.com/taojeff/MarkDownPod'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'GIKICoder' => 'giki.biu@gmail.com' }
  s.source           = { :git => 'https://github.com/taojeff/MarkDownPod.git', :tag => s.version.to_s }

  s.ios.deployment_target = '13.0'
  s.swift_version = '5.0'
  s.static_framework = true

  s.source_files = 'Sources/**/*.swift'
  
  # Resource files from Assets directory
  s.resources = [
    'Sources/Assets/**/*'
  ]
  
  # Dependencies
  s.dependency 'YSTSwiftMarkdownPod', '1.0.1.2'
  s.dependency 'SwiftMath-pod', '2.0.1.pod'
  s.dependency 'MathJaxSwiftPod', '3.2.2.1'
  s.dependency 'MPITextKit','0.2.4'
  s.dependency 'SwiftSoup', '2.11.3'
  s.dependency 'SDWebImage', '5.21.7'
  
  # Frameworks
  s.frameworks = 'UIKit', 'Foundation', 'WebKit', 'JavaScriptCore', 'Photos'
  
  # Additional settings
  s.requires_arc = true
  
  # Compiler conditions for resource loading
  s.pod_target_xcconfig = {
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS' => 'COCOAPODS'
  }
end
