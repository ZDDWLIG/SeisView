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
    /// 相对容差（带绝对下限）：|a-b| <= rel * max(1, |b|)。用于数量级较大的数据，
    /// 此时 Float32 的 ULP 可能远超绝对容差，相对比较才“有意义但不脆弱”。
    func checkRel<T: FloatingPoint>(_ a: T, _ b: T, _ rel: T, _ msg: String) {
        let tol = rel * max(1, abs(b))
        check(abs(a - b) <= tol, "\(msg) (\(a) ≈ \(b), tol \(tol))")
    }
    func finish() -> Never {
        print("== \(passes) passed, \(failures) failed ==")
        exit(failures == 0 ? 0 : 1)
    }
}
