import Foundation

@MainActor
final class Harness {
    private var failures = 0, passes = 0
    func check(_ cond: Bool, _ msg: String) {
        if cond { passes += 1; print("PASS \(msg)") }
        else { failures += 1; print("FAIL \(msg)") }
    }
    func checkClose<T: FloatingPoint>(_ a: T, _ b: T, _ tol: T, _ msg: String) {
        check(abs(a - b) <= tol, "\(msg) (\(a) ≈ \(b))")
    }
    func finish() -> Never {
        print("== \(passes) passed, \(failures) failed ==")
        exit(failures == 0 ? 0 : 1)
    }
}
