import Foundation

let delegate = HelperToolDelegate()
let listener = NSXPCListener(machServiceName: "com.processscope.helper")
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
