import SegyKit

@MainActor
func runAll() {
    let h = Harness()
    h.check(SegyKit.version == "0.1.0", "SegyKit version")
    h.finish()
}
runAll()
