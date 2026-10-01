import AppKit
import Darwin

enum SingleInstance {
    static let showSettings=Notification.Name("com.pawsync.desktop.showSettings")
    private static var descriptor:Int32 = -1
    static func acquire() throws -> Bool {
        let directory=PetStore.root.appendingPathComponent("Runtime",isDirectory:true)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        descriptor=open(directory.appendingPathComponent("instance.lock").path,O_CREAT|O_RDWR|O_NOFOLLOW,0o600)
        guard descriptor >= 0 else { throw PawError.message("Could not open PawSync’s instance lock.") }
        if flock(descriptor,LOCK_EX|LOCK_NB) != 0 {
            close(descriptor); descriptor = -1
            DistributedNotificationCenter.default().postNotificationName(showSettings,object:nil,userInfo:nil,deliverImmediately:true)
            NSRunningApplication.runningApplications(withBundleIdentifier:Bundle.main.bundleIdentifier ?? "com.pawsync.desktop").first(where:{$0.processIdentifier != ProcessInfo.processInfo.processIdentifier})?.activate(options:[])
            return false
        }
        return true
    }
}
