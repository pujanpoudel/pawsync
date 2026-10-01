import AppKit
import Combine
import Darwin
import IOKit.ps

struct ResourceSample {
    var cpu:Double?; var memory:Double?; var disk:Double?; var battery:Int?; var upload:Double?; var download:Double?
    var captured:Date=Date()
}
@MainActor final class ResourceMonitor:ObservableObject {
    @Published private(set) var sample=ResourceSample()
    @Published var alerts=false
    var suspended=false
    var onWarning:((String)->Void)?
    private let features:NativeFeatureRegistry
    private var timer:Timer?
    private var previousCPU:[UInt64]?
    private var previousNetwork:(sent:UInt64,received:UInt64,time:Date)?
    private var hotSamples=0
    private var lastWarning=Date.distantPast
    init(features:NativeFeatureRegistry,startTimer:Bool=true) {
        self.features=features
        if startTimer { timer=Timer.scheduledTimer(withTimeInterval:15,repeats:true) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }; timer?.tolerance=3 }
    }
    func refresh(now:Date=Date()) {
        guard !suspended,features.contains("openpets.system-resources") else { previousCPU=nil; previousNetwork=nil; hotSamples=0; return }
        var result=ResourceSample(captured:now)
        var cpu=host_cpu_load_info(),count=mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size/MemoryLayout<integer_t>.size)
        let host=mach_host_self(); defer { mach_port_deallocate(mach_task_self_,host) }
        let status=withUnsafeMutablePointer(to:&cpu) { $0.withMemoryRebound(to:integer_t.self,capacity:Int(count)) { host_statistics(host,HOST_CPU_LOAD_INFO,$0,&count) } }
        if status == KERN_SUCCESS {
            let current=[UInt64(cpu.cpu_ticks.0),UInt64(cpu.cpu_ticks.1),UInt64(cpu.cpu_ticks.2),UInt64(cpu.cpu_ticks.3)]
            if let previousCPU,current.indices.allSatisfy({current[$0] >= previousCPU[$0]}) {
                let diff=zip(current,previousCPU).map(-),total=diff.reduce(0,+)
                if total > 0 { result.cpu=Double(total-diff[2])/Double(total)*100 }
            }
            previousCPU=current
        }
        var vm=vm_statistics64(),vmCount=mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size/MemoryLayout<integer_t>.size)
        let vmStatus=withUnsafeMutablePointer(to:&vm) { $0.withMemoryRebound(to:integer_t.self,capacity:Int(vmCount)) { host_statistics64(host,HOST_VM_INFO64,$0,&vmCount) } }
        var page:vm_size_t=0
        if vmStatus == KERN_SUCCESS,host_page_size(host,&page) == KERN_SUCCESS {
            let used=(UInt64(vm.active_count)+UInt64(vm.wire_count)+UInt64(vm.compressor_page_count))*UInt64(page)
            result.memory=min(100,Double(used)/Double(ProcessInfo.processInfo.physicalMemory)*100)
        }
        if let attributes=try? FileManager.default.attributesOfFileSystem(forPath:"/"),let total=attributes[.systemSize] as? NSNumber,let free=attributes[.systemFreeSize] as? NSNumber,total.doubleValue > 0 { result.disk=(1-free.doubleValue/total.doubleValue)*100 }
        if let info=IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),let sources=IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                if let data=IOPSGetPowerSourceDescription(info,source)?.takeUnretainedValue() as? [String:Any],let current=data[kIOPSCurrentCapacityKey] as? Int,let maximum=data[kIOPSMaxCapacityKey] as? Int,maximum > 0 { result.battery=max(0,min(100,current*100/maximum)); break }
            }
        }
        let network=Self.networkTotals()
        if let previousNetwork,now.timeIntervalSince(previousNetwork.time) > 0,network.sent >= previousNetwork.sent,network.received >= previousNetwork.received {
            result.upload=Double(network.sent-previousNetwork.sent)/now.timeIntervalSince(previousNetwork.time)
            result.download=Double(network.received-previousNetwork.received)/now.timeIntervalSince(previousNetwork.time)
        }
        previousNetwork=(network.sent,network.received,now); sample=result
        let busy=(result.cpu ?? 0) >= 90 || (result.memory ?? 0) >= 90
        hotSamples=busy ? hotSamples+1 : 0
        if alerts,hotSamples >= 2,now.timeIntervalSince(lastWarning) >= 600 { lastWarning=now; onWarning?("Your Mac is working hard. A little pause might help it catch up.") }
    }
    private static func networkTotals()->(sent:UInt64,received:UInt64) {
        var head:UnsafeMutablePointer<ifaddrs>?; guard getifaddrs(&head) == 0,let first=head else { return (0,0) }; defer { freeifaddrs(head) }
        var pointer:UnsafeMutablePointer<ifaddrs>?=first,sent:UInt64=0,received:UInt64=0
        while let current=pointer {
            let entry=current.pointee
            if entry.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),entry.ifa_flags & UInt32(IFF_UP) != 0,entry.ifa_flags & UInt32(IFF_LOOPBACK) == 0,let raw=entry.ifa_data {
                let data=raw.assumingMemoryBound(to:if_data.self).pointee; sent &+= UInt64(data.ifi_obytes); received &+= UInt64(data.ifi_ibytes)
            }
            pointer=entry.ifa_next
        }
        return (sent,received)
    }
    func shutdown() { timer?.invalidate(); timer=nil }
}
