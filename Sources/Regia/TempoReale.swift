import Foundation
import Darwin
import IOKit
import IOKit.ps

/// Una lettura dei dati in tempo reale (sola lettura, ogni secondo).
struct Campione {
    var cpu: Double = 0                 // 0...100
    var memoriaUsataGB: Double = 0
    var memoriaTotaleGB: Double = 0
    var reteGiu: Double = 0             // byte al secondo
    var reteSu: Double = 0
    var discoLettura: Double = 0        // byte al secondo
    var discoScrittura: Double = 0
    var batteria: Int? = nil
    var inCarica = false
    var alimentatore = false
    var watt: Double? = nil             // consumo a batteria
    var minutiRimasti: Int? = nil
    var termico = "normale"
    var termicoLivello = 0              // 0 normale … 3 critico
}

final class Misuratore {
    private var tickPrecedenti: [(uso: UInt64, totale: UInt64)] = []
    private var retePrecedente: (giu: UInt64, su: UInt64)?
    private var discoPrecedente: (l: UInt64, s: UInt64)?
    private var ultimo = Date()

    func campione() -> Campione {
        var c = Campione()
        let ora = Date()
        let secondi = max(ora.timeIntervalSince(ultimo), 0.2)
        ultimo = ora
        c.cpu = leggiCPU()
        (c.memoriaUsataGB, c.memoriaTotaleGB) = leggiMemoria()

        let r = leggiRete()
        if let p = retePrecedente {
            c.reteGiu = Double(differenza(r.giu, p.giu)) / secondi
            c.reteSu = Double(differenza(r.su, p.su)) / secondi
        }
        retePrecedente = r

        let d = leggiDisco()
        if let p = discoPrecedente {
            c.discoLettura = Double(d.l >= p.l ? d.l - p.l : 0) / secondi
            c.discoScrittura = Double(d.s >= p.s ? d.s - p.s : 0) / secondi
        }
        discoPrecedente = d

        leggiBatteria(&c)
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: (c.termico, c.termicoLivello) = (L("normal", "normale"), 0)
        case .fair: (c.termico, c.termicoLivello) = (L("warm", "tiepido"), 1)
        case .serious: (c.termico, c.termicoLivello) = (L("hot: slowing down", "caldo: rallenta"), 2)
        case .critical: (c.termico, c.termicoLivello) = (L("critical", "critico"), 3)
        @unknown default: (c.termico, c.termicoLivello) = ("?", 0)
        }
        return c
    }

    /// I contatori della rete sono a 32 bit: se ripartono da zero lo calcoliamo.
    private func differenza(_ nuovo: UInt64, _ vecchio: UInt64) -> UInt64 {
        nuovo >= vecchio ? nuovo - vecchio : (nuovo + (1 << 32)) - vecchio
    }

    private func leggiCPU() -> Double {
        var numero: natural_t = 0
        var info: processor_info_array_t?
        var quanti: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numero, &info, &quanti) == KERN_SUCCESS,
              let info else { return 0 }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(quanti) * MemoryLayout<integer_t>.stride)) }
        var nuovi: [(UInt64, UInt64)] = []
        var uso: UInt64 = 0, totale: UInt64 = 0
        for i in 0..<Int(numero) {
            let b = Int(CPU_STATE_MAX) * i
            let u = UInt64(UInt32(bitPattern: info[b + Int(CPU_STATE_USER)]))
            let s = UInt64(UInt32(bitPattern: info[b + Int(CPU_STATE_SYSTEM)]))
            let n = UInt64(UInt32(bitPattern: info[b + Int(CPU_STATE_NICE)]))
            let idle = UInt64(UInt32(bitPattern: info[b + Int(CPU_STATE_IDLE)]))
            let usoCore = u + s + n, totCore = usoCore + idle
            nuovi.append((usoCore, totCore))
            if i < tickPrecedenti.count {
                uso += usoCore &- tickPrecedenti[i].uso
                totale += totCore &- tickPrecedenti[i].totale
            }
        }
        tickPrecedenti = nuovi.map { (uso: $0.0, totale: $0.1) }
        return totale > 0 ? min(100, Double(uso) / Double(totale) * 100) : 0
    }

    private func leggiMemoria() -> (Double, Double) {
        var stat = vm_statistics64()
        var quanti = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &stat) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(quanti)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &quanti) }
        }
        let totale = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        guard r == KERN_SUCCESS else { return (0, totale) }
        let pagina = Double(vm_kernel_page_size)
        // Come Monitoraggio Attività: memoria app + wired + compressa
        let app = Double(stat.internal_page_count) - Double(stat.purgeable_count)
        let usata = (app + Double(stat.wire_count) + Double(stat.compressor_page_count)) * pagina / 1_073_741_824
        return (min(usata, totale), totale)
    }

    private func leggiRete() -> (giu: UInt64, su: UInt64) {
        var lista: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&lista) == 0, let primo = lista else { return (0, 0) }
        defer { freeifaddrs(lista) }
        var giu: UInt64 = 0, su: UInt64 = 0
        var p: UnsafeMutablePointer<ifaddrs>? = primo
        while let a = p {
            let nome = String(cString: a.pointee.ifa_name)
            if let addr = a.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK), nome.hasPrefix("en"),
               let dati = a.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                giu += UInt64(dati.pointee.ifi_ibytes)
                su += UInt64(dati.pointee.ifi_obytes)
            }
            p = a.pointee.ifa_next
        }
        return (giu % (1 << 32), su % (1 << 32))
    }

    private func leggiDisco() -> (l: UInt64, s: UInt64) {
        var iteratore: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iteratore) == KERN_SUCCESS else { return (0, 0) }
        defer { IOObjectRelease(iteratore) }
        var l: UInt64 = 0, s: UInt64 = 0
        var servizio = IOIteratorNext(iteratore)
        while servizio != 0 {
            if let st = IORegistryEntryCreateCFProperty(servizio, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] {
                l += (st["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                s += (st["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            }
            IOObjectRelease(servizio)
            servizio = IOIteratorNext(iteratore)
        }
        return (l, s)
    }

    private func leggiBatteria(_ c: inout Campione) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let lista = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for fonte in lista {
            guard let d = IOPSGetPowerSourceDescription(info, fonte)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            c.batteria = d[kIOPSCurrentCapacityKey] as? Int
            c.inCarica = (d[kIOPSIsChargingKey] as? Bool) ?? false
            c.alimentatore = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            if let m = d[kIOPSTimeToEmptyKey] as? Int, m > 0, !c.alimentatore { c.minutiRimasti = m }
        }
        let servizio = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard servizio != 0 else { return }
        defer { IOObjectRelease(servizio) }
        func numero(_ k: String) -> Int? {
            (IORegistryEntryCreateCFProperty(servizio, k as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.intValue
        }
        if !c.alimentatore, let v = numero("Voltage"), let a = numero("Amperage") {
            c.watt = abs(Double(v) * Double(a)) / 1_000_000
        }
    }
}

func formatoVelocita(_ b: Double) -> String {
    if b < 1024 { return "0 KB/s" }
    if b < 1_048_576 { return String(format: "%.0f KB/s", b / 1024) }
    return decimale(b / 1_048_576) + " MB/s"
}
