import Foundation
import CryptoKit

/// Aggiornamenti da GitHub, come in Regia Windows: all'avvio legge versione.json; se c'è una versione
/// più nuova compare il pulsante "Aggiorna". Solo dopo conferma: scarica lo zip, controlla l'impronta
/// SHA-256, l'identificativo, la versione e la firma, salva l'app attuale in Versioni e la sostituisce.
/// Modifiche, backup, registro e profili (in Application Support) non vengono toccati.
enum Aggiornamenti {
    static let identificativo = "io.github.sm-bc.regia"
    static let urlPredefinito = "https://raw.githubusercontent.com/sm-bc/regia-mac/main/versione.json"

    struct Info: Codable, Equatable {
        let versione: String
        let url: String
        let sha256: String
        var note: String? = nil
    }

    static var versioneAttuale: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    /// Si può cambiare solo per le prove (variabile d'ambiente).
    static var urlVersione: String {
        ProcessInfo.processInfo.environment["REGIA_URL_AGGIORNAMENTI"] ?? urlPredefinito
    }

    /// "2.10" > "2.9" > "2.1": confronto numero per numero.
    static func piuNuova(_ a: String, di b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    /// Il pacchetto deve stare su GitHub (o sullo stesso sito di versione.json), sempre in https.
    /// Per le prove in locale sono ammessi file:// solo se anche versione.json è un file locale.
    static func fidato(versione: String, pacchetto: String) -> Bool {
        guard let v = URL(string: versione), let p = URL(string: pacchetto) else { return false }
        if v.isFileURL { return p.isFileURL }
        guard v.scheme == "https", p.scheme == "https", let hv = v.host, let hp = p.host else { return false }
        if hv == hp { return true }
        let github = { (h: String) in h == "github.com" || h.hasSuffix(".github.com") || h.hasSuffix("githubusercontent.com") }
        return github(hv) && github(hp)
    }

    static func valida(_ i: Info, da urlVersione: String) throws {
        guard i.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
            throw ErroreRegia.messaggio(L("Invalid versione.json: SHA-256 fingerprint missing or wrong.", "versione.json non valido: impronta SHA-256 mancante o sbagliata."))
        }
        guard i.versione.range(of: #"^\d+(\.\d+)*$"#, options: .regularExpression) != nil else {
            throw ErroreRegia.messaggio(L("Invalid versione.json: version number", "versione.json non valido: numero di versione") + " \"\(i.versione)\".")
        }
        guard fidato(versione: urlVersione, pacchetto: i.url) else {
            throw ErroreRegia.messaggio(L("The package is on an untrusted site (\(i.url)): ignored.", "Il pacchetto è su un sito non fidato (\(i.url)): ignorato."))
        }
    }

    /// Restituisce l'aggiornamento se c'è una versione più nuova, nil se Regia è già aggiornata.
    static func controlla(da indirizzo: String = urlVersione, attuale: String = versioneAttuale) async throws -> Info? {
        guard let url = URL(string: indirizzo) else { throw ErroreRegia.messaggio(L("Invalid update address.", "Indirizzo aggiornamenti non valido.")) }
        var richiesta = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        richiesta.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let (dati, risposta) = try await URLSession.shared.data(for: richiesta)
        if let h = risposta as? HTTPURLResponse, h.statusCode != 200 {
            throw ErroreRegia.messaggio(L("GitHub replied \(h.statusCode).", "GitHub ha risposto \(h.statusCode)."))
        }
        let info = try JSONDecoder().decode(Info.self, from: dati)
        try valida(info, da: indirizzo)
        return piuNuova(info.versione, di: attuale) ? info : nil
    }

    static func sha256(_ file: URL) throws -> String {
        let d = try Data(contentsOf: file)
        return SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined()
    }

    /// Scarica, controlla e sostituisce l'app. Restituisce dove è stata salvata la versione vecchia.
    @discardableResult
    static func installa(_ i: Info, da indirizzo: String = urlVersione, app: URL, cartellaVersioni: URL,
                         registro: (String) -> Void) async throws -> URL {
        try valida(i, da: indirizzo)
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("regia-aggiornamento-\(UUID().uuidString.prefix(8))")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        // 1. Scarica
        guard let sorgente = URL(string: i.url) else { throw ErroreRegia.messaggio(L("Invalid package address.", "Indirizzo del pacchetto non valido.")) }
        let zip = tmp.appendingPathComponent("Regia.zip")
        if sorgente.isFileURL {
            try fm.copyItem(at: sorgente, to: zip)
        } else {
            let (scaricato, risposta) = try await URLSession.shared.download(from: sorgente)
            if let h = risposta as? HTTPURLResponse, h.statusCode != 200 { throw ErroreRegia.messaggio(L("Download failed (\(h.statusCode)).", "Download non riuscito (\(h.statusCode)).")) }
            try fm.moveItem(at: scaricato, to: zip)
        }

        // 2. Impronta SHA-256
        let impronta = try sha256(zip)
        guard impronta == i.sha256.lowercased() else {
            throw ErroreRegia.messaggio(L("The downloaded file doesn't match the expected SHA-256 fingerprint: update cancelled, Regia was not changed.", "Il file scaricato non corrisponde all'impronta SHA-256 attesa: aggiornamento annullato, Regia non è stata modificata."))
        }
        registro(L("Package \(i.versione) downloaded and verified (SHA-256 \(impronta))", "Pacchetto \(i.versione) scaricato e verificato (SHA-256 \(impronta))"))

        // 3. Estrai e controlla il contenuto
        let estratto = tmp.appendingPathComponent("x")
        let r = esegui("/usr/bin/ditto", ["-x", "-k", zip.path, estratto.path])
        guard r.ok else { throw ErroreRegia.messaggio(L("Can't open the zip", "Non riesco ad aprire lo zip") + ": \(r.errore)") }
        guard let nuova = (try? fm.contentsOfDirectory(at: estratto, includingPropertiesForKeys: nil))?.first(where: { $0.pathExtension == "app" }) else {
            throw ErroreRegia.messaggio(L("Regia.app is missing from the package.", "Nel pacchetto manca Regia.app."))
        }
        let info = NSDictionary(contentsOf: nuova.appendingPathComponent("Contents/Info.plist")) as? [String: Any]
        guard info?["CFBundleIdentifier"] as? String == identificativo else {
            throw ErroreRegia.messaggio(L("The package doesn't contain Regia (different identifier).", "Il pacchetto non contiene Regia (identificativo diverso)."))
        }
        guard info?["CFBundleShortVersionString"] as? String == i.versione else {
            throw ErroreRegia.messaggio(L("The version inside the package isn't \(i.versione).", "La versione dentro il pacchetto non è la \(i.versione)."))
        }
        let firma = esegui("/usr/bin/codesign", ["--verify", "--deep", "--strict", nuova.path])
        guard firma.ok else { throw ErroreRegia.messaggio(L("The downloaded app's signature is not valid", "La firma dell'app scaricata non è valida") + ": \(firma.errore)") }
        esegui("/usr/bin/xattr", ["-dr", "com.apple.quarantine", nuova.path])

        // 4. Salva la versione attuale in Versioni e metti al suo posto quella nuova
        try fm.createDirectory(at: cartellaVersioni, withIntermediateDirectories: true)
        let vecchiaVersione = (NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"] as? String) ?? "precedente"
        var copia = cartellaVersioni.appendingPathComponent("Regia \(vecchiaVersione).app")
        if fm.fileExists(atPath: copia.path) {
            let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmm"
            copia = cartellaVersioni.appendingPathComponent("Regia \(vecchiaVersione) \(f.string(from: Date())).app")
        }
        if fm.fileExists(atPath: app.path) { try fm.moveItem(at: app, to: copia) }
        do {
            try fm.moveItem(at: nuova, to: app)
        } catch {
            if fm.fileExists(atPath: copia.path) { try? fm.moveItem(at: copia, to: app) }   // rimetti la vecchia
            throw ErroreRegia.messaggio(L("Can't replace the app", "Non riesco a sostituire l'app") + ": \(error.localizedDescription)")
        }
        registro(L("Regia updated to \(i.versione); version \(vecchiaVersione) is in \(copia.path)", "Regia aggiornata alla \(i.versione); la versione \(vecchiaVersione) è in \(copia.path)"))

        // Tieni solo le ultime 3 versioni vecchie
        let vecchie = ((try? fm.contentsOfDirectory(at: cartellaVersioni, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.pathExtension == "app" }
            .sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                    > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
        for v in vecchie.dropFirst(3) { try? fm.removeItem(at: v) }
        return copia
    }

    /// Riapre Regia dopo l'aggiornamento.
    static func riapri(_ app: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", app.path]
        try? p.run()
    }
}
