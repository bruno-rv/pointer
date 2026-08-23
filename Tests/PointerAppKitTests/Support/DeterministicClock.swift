final class DeterministicClock {
    var nowNanoseconds: UInt64

    init(nowNanoseconds: UInt64 = 0) {
        self.nowNanoseconds = nowNanoseconds
    }

    func advance(by nanoseconds: UInt64) {
        nowNanoseconds += nanoseconds
    }
}
