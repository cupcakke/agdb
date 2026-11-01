const std = @import("std");
const builtin = @import("builtin");
const atomic = std.atomic;

comptime {
    const minimum_zig_version = std.SemanticVersion{ .major = 0, .minor = 15, .patch = 0 };
    if (builtin.zig_version.order(minimum_zig_version) == .lt) {
        @compileError("this module requires Zig 0.15.0 or newer");
    }
}

pub const is_x86_64 = builtin.cpu.arch == .x86_64;
pub const is_aarch64 = builtin.cpu.arch == .aarch64 or builtin.cpu.arch == .aarch64_be;
pub const is_riscv64 = builtin.cpu.arch == .riscv64;
pub const has_hardware_counter = is_x86_64 or is_aarch64 or is_riscv64;
const is_linux = builtin.os.tag == .linux;
const has_std_instant = @hasDecl(std.time, "Instant");

pub const rdrand_retry_limit: u32 = 10;
pub const rdseed_retry_limit: u32 = 100;

pub const HwRngError = error{ Unsupported, Unavailable };
pub const TimerError = error{ CpuMigrated, CounterWentBackward };
pub const CpuTimerError = TimerError || error{ InvalidRate, OutOfRange };
pub const ClockError = error{MonotonicClockUnavailable};
pub const FreqError = TimerError || error{ InvalidSampleDuration, MonotonicClockUnavailable, ZeroElapsed, FrequencyOutOfRange };
pub const SequenceError = error{Exhausted};
pub const RangeError = error{InvalidRange};

pub const TscReading = struct {
    tsc: u64,
    cpu_id: ?u32,
    aux: ?u32,
};

pub const TscStamp = struct {
    tsc: u64,
    cpu_id: ?u32,
};

const CpuidResult = struct {
    eax: u32,
    ebx: u32,
    ecx: u32,
    edx: u32,
};

const X86Features = struct {
    rdtscp: bool,
    rdrand: bool,
    rdseed: bool,
    invariant_tsc: bool,
    tsc_hz_from_cpuid: ?u64,
};

const Once = struct {
    state: atomic.Value(u8) = atomic.Value(u8).init(0),

    fn call(self: *Once, comptime func: fn () void) void {
        if (self.state.load(.acquire) == 2) return;
        if (self.state.cmpxchgStrong(0, 1, .acquire, .acquire) == null) {
            func();
            self.state.store(2, .release);
            return;
        }
        while (self.state.load(.acquire) != 2) {
            std.atomic.spinLoopHint();
        }
    }
};

const KernelTimespec = extern struct {
    sec: isize,
    nsec: isize,
};

const linux_clock_realtime: usize = 0;
const linux_clock_monotonic: usize = 1;
const linux_eintr: isize = 4;

var x86_features: X86Features = undefined;
var x86_features_once = Once{};
var monotonic_epoch_ns: u64 = 0;
var monotonic_epoch_valid: bool = false;
var instant_epoch: if (has_std_instant) std.time.Instant else void = undefined;
var monotonic_epoch_once = Once{};
var fence_anchor = atomic.Value(u32).init(0);

fn cpuid(leaf: u32, subleaf: u32) CpuidResult {
    var eax: u32 = undefined;
    var ebx: u32 = undefined;
    var ecx: u32 = undefined;
    var edx: u32 = undefined;
    asm volatile ("cpuid"
        : [eax] "={eax}" (eax),
          [ebx] "={ebx}" (ebx),
          [ecx] "={ecx}" (ecx),
          [edx] "={edx}" (edx),
        : [leaf] "{eax}" (leaf),
          [subleaf] "{ecx}" (subleaf),
    );
    return .{ .eax = eax, .ebx = ebx, .ecx = ecx, .edx = edx };
}

fn detectX86Features() void {
    var features = X86Features{
        .rdtscp = false,
        .rdrand = false,
        .rdseed = false,
        .invariant_tsc = false,
        .tsc_hz_from_cpuid = null,
    };
    const basic = cpuid(0, 0);
    const max_basic_leaf = basic.eax;
    if (max_basic_leaf >= 1) {
        const leaf1 = cpuid(1, 0);
        features.rdrand = ((leaf1.ecx >> 30) & 1) == 1;
    }
    if (max_basic_leaf >= 7) {
        const leaf7 = cpuid(7, 0);
        features.rdseed = ((leaf7.ebx >> 18) & 1) == 1;
    }
    if (max_basic_leaf >= 0x15) {
        const leaf15 = cpuid(0x15, 0);
        if (leaf15.eax != 0 and leaf15.ebx != 0 and leaf15.ecx != 0) {
            const hz: u128 = (@as(u128, leaf15.ecx) * @as(u128, leaf15.ebx)) / @as(u128, leaf15.eax);
            features.tsc_hz_from_cpuid = std.math.cast(u64, hz);
        }
    }
    const extended = cpuid(0x80000000, 0);
    const max_extended_leaf = extended.eax;
    if (max_extended_leaf >= 0x80000001) {
        const ext1 = cpuid(0x80000001, 0);
        features.rdtscp = ((ext1.edx >> 27) & 1) == 1;
    }
    if (max_extended_leaf >= 0x80000007) {
        const ext7 = cpuid(0x80000007, 0);
        features.invariant_tsc = ((ext7.edx >> 8) & 1) == 1;
    }
    x86_features = features;
}

fn x86Features() X86Features {
    x86_features_once.call(detectX86Features);
    return x86_features;
}

fn linuxSyscallFailed(rc: usize) bool {
    const signed: isize = @bitCast(rc);
    return signed < 0 and signed > -4096;
}

fn linuxSyscallErrno(rc: usize) isize {
    const signed: isize = @bitCast(rc);
    return -signed;
}

fn linuxClockRead(clock_id: usize) ?KernelTimespec {
    var ts = KernelTimespec{ .sec = 0, .nsec = 0 };
    const rc = std.os.linux.syscall2(.clock_gettime, clock_id, @intFromPtr(&ts));
    if (rc != 0) return null;
    return ts;
}

fn linuxClockNs(clock_id: usize) ?u64 {
    const ts = linuxClockRead(clock_id) orelse return null;
    if (ts.sec < 0 or ts.nsec < 0) return null;
    const sec: u64 = @intCast(ts.sec);
    const nsec: u64 = @intCast(ts.nsec);
    const sec_ns = std.math.mul(u64, sec, std.time.ns_per_s) catch return null;
    return std.math.add(u64, sec_ns, nsec) catch return null;
}

fn initMonotonicEpoch() void {
    if (comptime is_linux) {
        if (linuxClockNs(linux_clock_monotonic)) |now| {
            monotonic_epoch_ns = now;
            monotonic_epoch_valid = true;
        } else {
            monotonic_epoch_valid = false;
        }
    } else if (comptime has_std_instant) {
        if (std.time.Instant.now()) |now| {
            instant_epoch = now;
            monotonic_epoch_valid = true;
        } else |_| {
            monotonic_epoch_valid = false;
        }
    } else {
        @compileError("no monotonic clock available on this platform");
    }
}

pub fn monotonicNanosChecked() ClockError!u64 {
    monotonic_epoch_once.call(initMonotonicEpoch);
    if (!monotonic_epoch_valid) return error.MonotonicClockUnavailable;
    if (comptime is_linux) {
        const now = linuxClockNs(linux_clock_monotonic) orelse return error.MonotonicClockUnavailable;
        return now -| monotonic_epoch_ns;
    } else if (comptime has_std_instant) {
        const now = std.time.Instant.now() catch return error.MonotonicClockUnavailable;
        return now.since(instant_epoch);
    } else {
        @compileError("no monotonic clock available on this platform");
    }
}

pub fn monotonicNanos() u64 {
    return monotonicNanosChecked() catch @panic("monotonic clock unavailable on this platform");
}

pub fn wallClockTimestampUs() i64 {
    if (comptime is_linux) {
        const ts = linuxClockRead(linux_clock_realtime) orelse @panic("realtime clock unavailable on this platform");
        const sec: i64 = @intCast(ts.sec);
        const nsec: i64 = @intCast(ts.nsec);
        return sec * std.time.us_per_s + @divTrunc(nsec, std.time.ns_per_us);
    } else if (comptime @hasDecl(std.time, "microTimestamp")) {
        return std.time.microTimestamp();
    } else {
        @compileError("no realtime clock available on this platform");
    }
}

pub fn sleepNanos(ns: u64) void {
    if (comptime is_linux) {
        var req = KernelTimespec{
            .sec = @intCast(ns / std.time.ns_per_s),
            .nsec = @intCast(ns % std.time.ns_per_s),
        };
        var rem = KernelTimespec{ .sec = 0, .nsec = 0 };
        while (true) {
            const rc = std.os.linux.syscall2(.nanosleep, @intFromPtr(&req), @intFromPtr(&rem));
            if (!linuxSyscallFailed(rc)) return;
            if (linuxSyscallErrno(rc) != linux_eintr) return;
            req = rem;
        }
    } else if (comptime @hasDecl(std.Thread, "sleep")) {
        std.Thread.sleep(ns);
    } else {
        const start = monotonicNanos();
        while (monotonicNanos() -| start < ns) {
            std.atomic.spinLoopHint();
        }
    }
}

fn osRandomBytes(out: []u8) void {
    if (comptime is_linux) {
        var i: usize = 0;
        while (i < out.len) {
            const rc = std.os.linux.syscall3(.getrandom, @intFromPtr(out[i..].ptr), out.len - i, 0);
            if (linuxSyscallFailed(rc)) {
                if (linuxSyscallErrno(rc) == linux_eintr) continue;
                @panic("getrandom failed");
            }
            i += rc;
        }
    } else if (comptime @hasDecl(std.crypto, "random")) {
        std.crypto.random.bytes(out);
    } else if (comptime builtin.link_libc and @hasDecl(std.c, "arc4random_buf")) {
        std.c.arc4random_buf(out.ptr, out.len);
    } else {
        @compileError("no operating system CSPRNG available on this platform");
    }
}

fn osRandom64() u64 {
    var buf: [8]u8 = undefined;
    osRandomBytes(&buf);
    return std.mem.readInt(u64, &buf, .little);
}

pub fn rdtscpSupported() bool {
    if (comptime is_x86_64) {
        return x86Features().rdtscp;
    } else {
        return false;
    }
}

pub fn rdrandSupported() bool {
    if (comptime is_x86_64) {
        if (comptime std.Target.x86.featureSetHas(builtin.cpu.features, .rdrnd)) return true;
        return x86Features().rdrand;
    } else {
        return false;
    }
}

pub fn rdseedSupported() bool {
    if (comptime is_x86_64) {
        if (comptime std.Target.x86.featureSetHas(builtin.cpu.features, .rdseed)) return true;
        return x86Features().rdseed;
    } else {
        return false;
    }
}

pub fn counterIsGloballySynchronized() bool {
    if (comptime is_x86_64) {
        return x86Features().invariant_tsc;
    } else {
        return true;
    }
}

pub fn nominalCounterFreqHz() ?u64 {
    if (comptime is_x86_64) {
        return x86Features().tsc_hz_from_cpuid;
    } else if (comptime is_aarch64) {
        var freq: u64 = undefined;
        asm volatile ("mrs %[freq], cntfrq_el0"
            : [freq] "=r" (freq),
        );
        if (freq == 0) return null;
        return freq;
    } else if (comptime is_riscv64) {
        return null;
    } else {
        return std.time.ns_per_s;
    }
}

pub fn currentCpuId() ?u32 {
    if (comptime is_linux) {
        var cpu: u32 = 0;
        var node: u32 = 0;
        const rc = std.os.linux.syscall3(.getcpu, @intFromPtr(&cpu), @intFromPtr(&node), 0);
        if (rc != 0) return null;
        return cpu;
    } else {
        return null;
    }
}

fn cpuIdFromTscAux(aux: u32) ?u32 {
    return switch (builtin.os.tag) {
        .linux => aux & 0xFFF,
        else => null,
    };
}

pub fn rdtsc() u64 {
    if (comptime is_x86_64) {
        var lo: u32 = undefined;
        var hi: u32 = undefined;
        asm volatile ("rdtsc"
            : [lo] "={eax}" (lo),
              [hi] "={edx}" (hi),
            :
            : .{ .memory = true });
        return (@as(u64, hi) << 32) | @as(u64, lo);
    } else if (comptime is_aarch64) {
        var value: u64 = undefined;
        asm volatile ("mrs %[value], cntvct_el0"
            : [value] "=r" (value),
            :
            : .{ .memory = true });
        return value;
    } else if (comptime is_riscv64) {
        var value: u64 = undefined;
        asm volatile ("rdtime %[value]"
            : [value] "=r" (value),
            :
            : .{ .memory = true });
        return value;
    } else {
        return monotonicNanos();
    }
}

pub fn rdtscp() TscReading {
    if (comptime is_x86_64) {
        if (x86Features().rdtscp) {
            var lo: u32 = undefined;
            var hi: u32 = undefined;
            var aux: u32 = undefined;
            asm volatile ("rdtscp"
                : [lo] "={eax}" (lo),
                  [hi] "={edx}" (hi),
                  [aux] "={ecx}" (aux),
                :
                : .{ .memory = true });
            return .{
                .tsc = (@as(u64, hi) << 32) | @as(u64, lo),
                .cpu_id = cpuIdFromTscAux(aux) orelse currentCpuId(),
                .aux = aux,
            };
        }
        lfence();
        const t = rdtsc();
        lfence();
        return .{ .tsc = t, .cpu_id = currentCpuId(), .aux = null };
    } else {
        lfence();
        const t = rdtsc();
        lfence();
        return .{ .tsc = t, .cpu_id = currentCpuId(), .aux = null };
    }
}

pub fn readStamp() TscStamp {
    const reading = rdtscp();
    return .{ .tsc = reading.tsc, .cpu_id = reading.cpu_id };
}

pub fn readStampBegin() TscStamp {
    lfence();
    const reading = rdtscp();
    lfence();
    return .{ .tsc = reading.tsc, .cpu_id = reading.cpu_id };
}

pub fn readStampEnd() TscStamp {
    const reading = rdtscp();
    lfence();
    return .{ .tsc = reading.tsc, .cpu_id = reading.cpu_id };
}

pub fn elapsedTicks(start: TscStamp, end: TscStamp) TimerError!u64 {
    if (!counterIsGloballySynchronized()) {
        if (start.cpu_id) |start_cpu| {
            if (end.cpu_id) |end_cpu| {
                if (start_cpu != end_cpu) return error.CpuMigrated;
            }
        }
    }
    if (end.tsc < start.tsc) return error.CounterWentBackward;
    return end.tsc - start.tsc;
}

pub fn lfence() void {
    if (comptime is_x86_64) {
        asm volatile ("lfence" ::: .{ .memory = true });
    } else if (comptime is_aarch64) {
        asm volatile ("isb" ::: .{ .memory = true });
    } else if (comptime is_riscv64) {
        asm volatile ("fence rw, rw" ::: .{ .memory = true });
    } else {
        _ = fence_anchor.fetchAdd(0, .seq_cst);
    }
}

pub fn mfence() void {
    if (comptime is_x86_64) {
        asm volatile ("mfence" ::: .{ .memory = true });
    } else if (comptime is_aarch64) {
        asm volatile ("dmb ish" ::: .{ .memory = true });
    } else if (comptime is_riscv64) {
        asm volatile ("fence rw, rw" ::: .{ .memory = true });
    } else {
        _ = fence_anchor.fetchAdd(0, .seq_cst);
    }
}

pub fn rdtscSerialized() u64 {
    lfence();
    const t = rdtsc();
    lfence();
    return t;
}

pub fn rdrand64() HwRngError!u64 {
    if (comptime is_x86_64) {
        if (!rdrandSupported()) return error.Unsupported;
        var value: u64 = undefined;
        var ok: u8 = undefined;
        asm volatile (
            \\rdrand %[val]
            \\setc %[ok]
            : [val] "=r" (value),
              [ok] "=r" (ok),
            :
            : .{ .cc = true });
        if (ok == 0) return error.Unavailable;
        return value;
    } else {
        return error.Unsupported;
    }
}

pub fn rdrandRetry(max_retries: u32) HwRngError!u64 {
    var attempt: u32 = 0;
    while (true) {
        if (rdrand64()) |value| {
            return value;
        } else |err| switch (err) {
            error.Unsupported => return error.Unsupported,
            error.Unavailable => {
                if (attempt >= max_retries) return error.Unavailable;
                attempt += 1;
                std.atomic.spinLoopHint();
            },
        }
    }
}

pub fn rdseed64() HwRngError!u64 {
    if (comptime is_x86_64) {
        if (!rdseedSupported()) return error.Unsupported;
        var value: u64 = undefined;
        var ok: u8 = undefined;
        asm volatile (
            \\rdseed %[val]
            \\setc %[ok]
            : [val] "=r" (value),
              [ok] "=r" (ok),
            :
            : .{ .cc = true });
        if (ok == 0) return error.Unavailable;
        return value;
    } else {
        return error.Unsupported;
    }
}

pub fn rdseedRetry(max_retries: u32) HwRngError!u64 {
    var attempt: u32 = 0;
    while (true) {
        if (rdseed64()) |value| {
            return value;
        } else |err| switch (err) {
            error.Unsupported => return error.Unsupported,
            error.Unavailable => {
                if (attempt >= max_retries) return error.Unavailable;
                attempt += 1;
                std.atomic.spinLoopHint();
            },
        }
    }
}

pub const TscSequencer = struct {
    counter: atomic.Value(u64) align(64),
    base: TscStamp,

    pub fn init() TscSequencer {
        return .{
            .counter = atomic.Value(u64).init(0),
            .base = readStampBegin(),
        };
    }

    pub fn next(self: *TscSequencer) SequenceError!u128 {
        const sequence = try self.nextMonotonic();
        const t = rdtscSerialized();
        return (@as(u128, sequence) << 64) | @as(u128, t);
    }

    pub fn nextMonotonic(self: *TscSequencer) SequenceError!u64 {
        var current = self.counter.load(.monotonic);
        while (true) {
            if (current == std.math.maxInt(u64)) return error.Exhausted;
            if (self.counter.cmpxchgWeak(current, current + 1, .acq_rel, .monotonic)) |observed| {
                current = observed;
            } else {
                return current;
            }
        }
    }

    pub fn peek(self: *const TscSequencer) u64 {
        return self.counter.load(.acquire);
    }

    pub fn tscDelta(self: *const TscSequencer) TimerError!u64 {
        return elapsedTicks(self.base, readStampEnd());
    }
};

pub const RngSource = enum {
    rdrand,
    os_csprng,
};

pub const HardwareRng = struct {
    source: RngSource,
    fallback_count: atomic.Value(u64),

    pub fn init() HardwareRng {
        return .{
            .source = if (rdrandSupported()) .rdrand else .os_csprng,
            .fallback_count = atomic.Value(u64).init(0),
        };
    }

    pub fn next64(self: *HardwareRng) u64 {
        if (self.source == .rdrand) {
            if (rdrandRetry(rdrand_retry_limit)) |value| {
                return value;
            } else |_| {
                _ = self.fallback_count.fetchAdd(1, .monotonic);
            }
        }
        return osRandom64();
    }

    pub fn tryNext64Hardware(self: *const HardwareRng) HwRngError!u64 {
        if (self.source != .rdrand) return error.Unsupported;
        return rdrandRetry(rdrand_retry_limit);
    }

    pub fn fallbacks(self: *const HardwareRng) u64 {
        return self.fallback_count.load(.monotonic);
    }

    pub fn nextBytes(self: *HardwareRng, out: []u8) void {
        var i: usize = 0;
        while (out.len - i >= 8) : (i += 8) {
            std.mem.writeInt(u64, out[i..][0..8], self.next64(), .little);
        }
        const remaining = out.len - i;
        if (remaining > 0) {
            var tail: [8]u8 = undefined;
            std.mem.writeInt(u64, &tail, self.next64(), .little);
            @memcpy(out[i..], tail[0..remaining]);
        }
    }

    fn uniformBelow(self: *HardwareRng, bound: u64) u64 {
        std.debug.assert(bound > 0);
        const threshold = (0 -% bound) % bound;
        while (true) {
            const value = self.next64();
            if (value >= threshold) return value % bound;
        }
    }

    pub fn nextInRangeLessThan(self: *HardwareRng, lower: u64, upper_exclusive: u64) RangeError!u64 {
        if (lower >= upper_exclusive) return error.InvalidRange;
        return lower + self.uniformBelow(upper_exclusive - lower);
    }

    pub fn nextInRangeAtMost(self: *HardwareRng, lower: u64, upper_inclusive: u64) RangeError!u64 {
        if (lower > upper_inclusive) return error.InvalidRange;
        if (lower == 0 and upper_inclusive == std.math.maxInt(u64)) return self.next64();
        return lower + self.uniformBelow(upper_inclusive - lower + 1);
    }
};

pub const CpuTimer = struct {
    start: TscStamp,

    pub fn begin() CpuTimer {
        return .{ .start = readStampBegin() };
    }

    pub fn elapsedCycles(self: *const CpuTimer) TimerError!u64 {
        return elapsedTicks(self.start, readStampEnd());
    }

    pub fn elapsedNs(self: *const CpuTimer, counter_freq_hz: u64) CpuTimerError!u64 {
        if (counter_freq_hz == 0) return error.InvalidRate;
        const cycles = try self.elapsedCycles();
        const ns: u128 = (@as(u128, cycles) * @as(u128, std.time.ns_per_s)) / @as(u128, counter_freq_hz);
        return std.math.cast(u64, ns) orelse error.OutOfRange;
    }

    pub fn elapsedNsApprox(self: *const CpuTimer, cycles_per_ns: f64) CpuTimerError!u64 {
        if (!std.math.isFinite(cycles_per_ns) or cycles_per_ns <= 0.0) return error.InvalidRate;
        const cycles = try self.elapsedCycles();
        const ns = @as(f64, @floatFromInt(cycles)) / cycles_per_ns;
        if (!std.math.isFinite(ns) or ns < 0.0 or ns >= 18446744073709551616.0) return error.OutOfRange;
        return @intFromFloat(ns);
    }
};

pub fn estimateTscFreqHz(sample_ms: u64) FreqError!u64 {
    if (sample_ms == 0) return error.InvalidSampleDuration;
    const target_ns = std.math.mul(u64, sample_ms, std.time.ns_per_ms) catch return error.InvalidSampleDuration;
    const begin_ns = try monotonicNanosChecked();
    const start = readStampBegin();
    while ((try monotonicNanosChecked()) -| begin_ns < target_ns) {
        std.atomic.spinLoopHint();
    }
    const end = readStampEnd();
    const elapsed_ns = (try monotonicNanosChecked()) -| begin_ns;
    const ticks = try elapsedTicks(start, end);
    if (elapsed_ns == 0) return error.ZeroElapsed;
    const hz: u128 = (@as(u128, ticks) * @as(u128, std.time.ns_per_s)) / @as(u128, elapsed_ns);
    return std.math.cast(u64, hz) orelse error.FrequencyOutOfRange;
}

pub fn main() void {
    const print = std.debug.print;
    print("architecture: {s}\n", .{@tagName(builtin.cpu.arch)});
    print("hardware counter: {}\n", .{has_hardware_counter});
    print("rdtscp supported: {}\n", .{rdtscpSupported()});
    print("rdrand supported: {}\n", .{rdrandSupported()});
    print("rdseed supported: {}\n", .{rdseedSupported()});
    print("counter globally synchronized: {}\n", .{counterIsGloballySynchronized()});
    if (nominalCounterFreqHz()) |hz| {
        print("nominal counter frequency: {d} Hz\n", .{hz});
    } else {
        print("nominal counter frequency: unknown\n", .{});
    }
    if (currentCpuId()) |cpu| {
        print("current cpu: {d}\n", .{cpu});
    } else {
        print("current cpu: unknown\n", .{});
    }
    print("monotonic ns: {d}\n", .{monotonicNanos()});
    print("wall clock us: {d}\n", .{wallClockTimestampUs()});

    const timer = CpuTimer.begin();

    var rng = HardwareRng.init();
    print("rng source: {s}\n", .{@tagName(rng.source)});
    print("random u64: {d}\n", .{rng.next64()});
    var bytes: [16]u8 = undefined;
    rng.nextBytes(&bytes);
    print("random bytes: ", .{});
    for (bytes) |byte| {
        print("{x:0>2}", .{byte});
    }
    print("\n", .{});
    if (rng.nextInRangeAtMost(1, 6)) |die| {
        print("dice roll: {d}\n", .{die});
    } else |err| {
        print("dice roll failed: {s}\n", .{@errorName(err)});
    }
    print("rng fallbacks: {d}\n", .{rng.fallbacks()});

    if (rdseedRetry(rdseed_retry_limit)) |seed| {
        print("rdseed value: {d}\n", .{seed});
    } else |err| {
        print("rdseed: {s}\n", .{@errorName(err)});
    }

    var seq = TscSequencer.init();
    if (seq.next()) |id| {
        print("sequence id: 0x{x}\n", .{id});
    } else |err| {
        print("sequence failed: {s}\n", .{@errorName(err)});
    }
    if (seq.next()) |id| {
        print("sequence id: 0x{x}\n", .{id});
    } else |err| {
        print("sequence failed: {s}\n", .{@errorName(err)});
    }
    if (seq.tscDelta()) |delta| {
        print("sequencer tsc delta: {d}\n", .{delta});
    } else |err| {
        print("sequencer tsc delta failed: {s}\n", .{@errorName(err)});
    }

    const freq = estimateTscFreqHz(10);
    if (freq) |hz| {
        print("estimated counter frequency: {d} Hz\n", .{hz});
    } else |err| {
        print("frequency estimate failed: {s}\n", .{@errorName(err)});
    }

    if (timer.elapsedCycles()) |cycles| {
        print("elapsed cycles: {d}\n", .{cycles});
    } else |err| {
        print("elapsed cycles failed: {s}\n", .{@errorName(err)});
    }
    if (freq) |hz| {
        if (timer.elapsedNs(hz)) |ns| {
            print("elapsed ns: {d}\n", .{ns});
        } else |err| {
            print("elapsed ns failed: {s}\n", .{@errorName(err)});
        }
    } else |_| {}
}

test "tsc reads" {
    const testing = std.testing;
    const a = readStampBegin();
    const b = readStampEnd();
    const same_cpu = a.cpu_id != null and b.cpu_id != null and a.cpu_id.? == b.cpu_id.?;
    if (counterIsGloballySynchronized() or same_cpu) {
        try testing.expect(b.tsc >= a.tsc);
    }
}

test "tsc sequencer monotonic" {
    const testing = std.testing;
    var seq = TscSequencer.init();
    const a = try seq.nextMonotonic();
    const b = try seq.nextMonotonic();
    const c = try seq.nextMonotonic();
    try testing.expect(b > a);
    try testing.expect(c > b);
    try testing.expectEqual(c + 1, seq.peek());
    const id1 = try seq.next();
    const id2 = try seq.next();
    try testing.expect(id2 > id1);
    seq.counter.store(std.math.maxInt(u64), .monotonic);
    try testing.expectError(error.Exhausted, seq.nextMonotonic());
    try testing.expectError(error.Exhausted, seq.next());
}

test "hardware rng instructions report support consistently" {
    const testing = std.testing;
    if (rdrandSupported()) {
        if (rdrandRetry(rdrand_retry_limit)) |_| {} else |err| {
            try testing.expect(err == error.Unavailable);
        }
    } else {
        try testing.expectError(error.Unsupported, rdrand64());
    }
    if (rdseedSupported()) {
        if (rdseedRetry(rdseed_retry_limit)) |_| {} else |err| {
            try testing.expect(err == error.Unavailable);
        }
    } else {
        try testing.expectError(error.Unsupported, rdseed64());
    }
}

test "hardware rng" {
    const testing = std.testing;
    var rng = HardwareRng.init();
    try testing.expect((rng.source == .rdrand) == rdrandSupported());
    const a = rng.next64();
    const b = rng.next64();
    try testing.expectEqual(a, try rng.nextInRangeAtMost(a, a));
    try testing.expectEqual(b, try rng.nextInRangeAtMost(b, b));
    var buf: [13]u8 = undefined;
    rng.nextBytes(&buf);
    rng.nextBytes(buf[0..0]);
    rng.nextBytes(buf[0..8]);
    rng.nextBytes(buf[0..3]);
    const v = try rng.nextInRangeLessThan(10, 20);
    try testing.expect(v >= 10 and v < 20);
    const w = try rng.nextInRangeAtMost(10, 20);
    try testing.expect(w >= 10 and w <= 20);
    try testing.expectError(error.InvalidRange, rng.nextInRangeLessThan(5, 5));
    try testing.expectError(error.InvalidRange, rng.nextInRangeLessThan(6, 5));
    try testing.expectError(error.InvalidRange, rng.nextInRangeAtMost(6, 5));
    if (rng.source == .rdrand) {
        if (rng.tryNext64Hardware()) |_| {} else |err| {
            try testing.expect(err == error.Unavailable);
        }
    } else {
        try testing.expectError(error.Unsupported, rng.tryNext64Hardware());
    }
}

test "cpu timer" {
    const testing = std.testing;
    const timer = CpuTimer.begin();
    const first = timer.elapsedCycles() catch |err| {
        try testing.expect(err == error.CpuMigrated or err == error.CounterWentBackward);
        return;
    };
    sleepNanos(std.time.ns_per_ms);
    const second = timer.elapsedCycles() catch |err| {
        try testing.expect(err == error.CpuMigrated or err == error.CounterWentBackward);
        return;
    };
    try testing.expect(second >= first);
    try testing.expectError(error.InvalidRate, timer.elapsedNs(0));
    try testing.expectError(error.InvalidRate, timer.elapsedNsApprox(0.0));
    try testing.expectError(error.InvalidRate, timer.elapsedNsApprox(-1.0));
    try testing.expectError(error.InvalidRate, timer.elapsedNsApprox(std.math.nan(f64)));
    try testing.expectError(error.InvalidRate, timer.elapsedNsApprox(std.math.inf(f64)));
    if (timer.elapsedNsApprox(1.0)) |ns| {
        try testing.expect(ns >= second);
    } else |err| {
        try testing.expect(err == error.CpuMigrated or err == error.CounterWentBackward);
    }
}

test "monotonic clock and wall clock" {
    const testing = std.testing;
    const a = try monotonicNanosChecked();
    sleepNanos(std.time.ns_per_ms);
    const b = try monotonicNanosChecked();
    try testing.expect(b >= a);
    try testing.expect(wallClockTimestampUs() > 0);
}

test "tsc frequency estimate" {
    const testing = std.testing;
    try testing.expectError(error.InvalidSampleDuration, estimateTscFreqHz(0));
    if (estimateTscFreqHz(5)) |hz| {
        try testing.expect(hz > 0);
    } else |err| {
        try testing.expect(err == error.CpuMigrated or err == error.CounterWentBackward or err == error.MonotonicClockUnavailable or err == error.ZeroElapsed);
    }
}
