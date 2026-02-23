import os

/// Centralized logging for ProcessScope
public enum PSLogger {
    public static let general = Logger(subsystem: "com.processscope", category: "General")
    public static let collectors = Logger(subsystem: "com.processscope", category: "Collectors")
    public static let polling = Logger(subsystem: "com.processscope", category: "Polling")
    public static let xpc = Logger(subsystem: "com.processscope", category: "XPC")
    public static let enrichment = Logger(subsystem: "com.processscope", category: "Enrichment")
    public static let actions = Logger(subsystem: "com.processscope", category: "Actions")
    public static let alerts = Logger(subsystem: "com.processscope", category: "Alerts")
    public static let ui = Logger(subsystem: "com.processscope", category: "UI")
}
