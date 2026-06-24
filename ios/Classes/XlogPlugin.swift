import Flutter
import Foundation

/// Flutter <-> mars-xlog glue. Native calls go through XLogBridge (ObjC++);
/// HTTP upload is handled in Dart.
public class XlogPlugin: NSObject, FlutterPlugin {
    private static let logDir: String = {
        let base = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let dir = (base as NSString).appendingPathComponent("xlog")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }()

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "com.polaris.xlog", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(XlogPlugin(), channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        // Only the cold paths (init / getLogDir / listLogFiles) run on the channel.
        // The hot path (log / setLevel / flush / close) and the appender open all
        // go straight to native via dart:ffi (see lib/src/xlog_ffi.dart); the
        // channel just resolves the app sandbox directories.
        switch call.method {
        case "init":
            let cacheDir = (XlogPlugin.logDir as NSString).appendingPathComponent("cache")
            try? FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
            result(["logDir": XlogPlugin.logDir, "cacheDir": cacheDir])
        case "getLogDir":
            result(XlogPlugin.logDir)
        case "listLogFiles":
            // mars writes the current day's file into the cache dir when
            // cacheDays > 0 and only moves it to logDir after cacheDays.
            // Scan both so today's log is always listed (cache wins on dupes).
            let fm = FileManager.default
            let cacheDir = (XlogPlugin.logDir as NSString).appendingPathComponent("cache")
            var byName = [String: [String: Any]]()
            for dir in [XlogPlugin.logDir, cacheDir] {
                let names = (try? fm.contentsOfDirectory(atPath: dir)) ?? []
                for name in names where name.hasSuffix(".xlog") {
                    let path = (dir as NSString).appendingPathComponent(name)
                    let size = ((try? fm.attributesOfItem(atPath: path))?[.size] as? Int) ?? 0
                    byName[name] = ["path": path, "name": name, "size": size]
                }
            }
            result(Array(byName.values))
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
