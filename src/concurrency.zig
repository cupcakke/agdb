const std = @import("std");
const atomic = std.atomic;
const header = @import("header.zig");
const wal_mod = @import("wal.zig");
const tsc = @import("tsc.zig");

comptime {
    _ = header;
    _ = wal_mod;
}

pub const PMUTEX_MAGIC: u32 = 0x504D5458;
pub const PRWLOCK_MAGIC: u32 = 0x5052574C;
pub const PCONDVAR_MAGIC: u32 = 0x50434E44;
pub const LOCK_MAGIC: u32 = PMUTEX_MAGIC;
pub const LOCK_VERSION: u32 = 1;

const MAX_SPIN_COUNT: u32 = 10_000;
const DEFAULT_SPIN_COUNT: u32 = 100;
const MAX_READER_TRACKS: usize = 128;
const GUARD_REGISTRY_CAPACITY: usize = 4096;

const GuardKind = enum(u8) {
    mutex,
    read,
    write,
};

const GuardEntry = struct {
    token: u64 = 0,
    kind: GuardKind = .mutex,
};

var guard_registry_mutex = std.Thread.Mutex{};
var guard_registry_entries = [_]GuardEntry{.{}} ** GUARD_REGISTRY_CAPACITY;
var guard_token_counter = atomic.Value(u64).init(1);

const ReaderTrack = struct {
    lock_addr: usize = 0,
    count: u32 = 0,
};

threadlocal var reader_tracking = [_]ReaderTrack{.{}} ** MAX_READER_TRACKS;

fn metadataChecksum(magic: u32, version: u32, kind: u32, reserved_len: u32) u32 {
    var h: u32 = 2166136261;
    h = (h ^ magic) *% 16777619;
    h = (h ^ version) *% 16777619;
    h = (h ^ kind) *% 16777619;
    h = (h ^ reserved_len) *% 16777619;
    if (h == 0) return 1;
    return h;
}

fn reservedAllZero(bytes: []const u8) bool {
    for (bytes) |b| {
        if (b != 0) return false;
    }
    return true;
}

fn currentThreadIdU64() u64 {
    if (tsc.is_simulation) {
        return FiberScheduler.currentId();
    }
    return @as(u64, @intCast(std.Thread.getCurrentId()));
}

fn boundedSpinCount(value: u32) u32 {
    return @min(value, MAX_SPIN_COUNT);
}

fn incrementCounter(counter: *atomic.Value(u32), max_value: u32) !void {
    while (true) {
        const current = counter.load(.acquire);
        if (current >= max_value) return error.CounterOverflow;
        if (counter.cmpxchgWeak(current, current + 1, .acq_rel, .monotonic) == null) return;
    }
}

fn decrementCounter(counter: *atomic.Value(u32)) void {
    const old = counter.fetchSub(1, .acq_rel);
    std.debug.assert(old > 0);
}

fn wakeAll(ptr: *const atomic.Value(u32)) void {
    if (tsc.is_simulation) return;
    std.Thread.Futex.wake(ptr, std.math.maxInt(u32));
}

fn registerGuard(kind: GuardKind) !u64 {
    const token = guard_token_counter.fetchAdd(1, .monotonic);
    if (token == 0) return error.TooManyGuards;

    guard_registry_mutex.lock();
    defer guard_registry_mutex.unlock();

    for (&guard_registry_entries) |*entry| {
        if (entry.token == 0) {
            entry.* = .{
                .token = token,
                .kind = kind,
            };
            return token;
        }
    }

    return error.TooManyGuards;
}

fn unregisterGuard(token: u64, kind: GuardKind) bool {
    if (token == 0) return false;

    guard_registry_mutex.lock();
    defer guard_registry_mutex.unlock();

    for (&guard_registry_entries) |*entry| {
        if (entry.token == token and entry.kind == kind) {
            entry.token = 0;
            entry.kind = .mutex;
            return true;
        }
    }

    return false;
}

fn readerTrackCount(lock_addr: usize) u32 {
    for (&reader_tracking) |*entry| {
        if (entry.lock_addr == lock_addr) return entry.count;
    }
    return 0;
}

fn readerTrackAdd(lock_addr: usize) !void {
    for (&reader_tracking) |*entry| {
        if (entry.lock_addr == lock_addr) {
            if (entry.count == std.math.maxInt(u32)) return error.CounterOverflow;
            entry.count += 1;
            return;
        }
    }

    for (&reader_tracking) |*entry| {
        if (entry.lock_addr == 0) {
            entry.lock_addr = lock_addr;
            entry.count = 1;
            return;
        }
    }

    return error.TooManyTrackedLocks;
}

fn readerTrackRemove(lock_addr: usize) !void {
    for (&reader_tracking) |*entry| {
        if (entry.lock_addr == lock_addr) {
            if (entry.count == 0) return error.NotOwner;
            entry.count -= 1;
            if (entry.count == 0) {
                entry.lock_addr = 0;
            }
            return;
        }
    }

    return error.NotOwner;
}

pub const PMutex = extern struct {
    magic: u32,
    version: u32,
    state: atomic.Value(u32),
    layout_padding0: u32,
    owner: atomic.Value(u64),
    waiters: atomic.Value(u32),
    spin_count: atomic.Value(u32),
    checksum: atomic.Value(u32),
    reserved: [36]u8,

    const STATE_UNLOCKED: u32 = 0;
    const STATE_LOCKED: u32 = 1;
    const STATE_CONTENDED: u32 = 2;
    const CHECKSUM_KIND: u32 = 1;
    const CHECKSUM_VALUE: u32 = metadataChecksum(PMUTEX_MAGIC, LOCK_VERSION, CHECKSUM_KIND, 36);

    pub fn init() PMutex {
        return PMutex{
            .magic = PMUTEX_MAGIC,
            .version = LOCK_VERSION,
            .state = atomic.Value(u32).init(STATE_UNLOCKED),
            .layout_padding0 = 0,
            .owner = atomic.Value(u64).init(0),
            .waiters = atomic.Value(u32).init(0),
            .spin_count = atomic.Value(u32).init(DEFAULT_SPIN_COUNT),
            .checksum = atomic.Value(u32).init(CHECKSUM_VALUE),
            .reserved = [_]u8{0} ** 36,
        };
    }

    fn validState(value: u32) bool {
        return value == STATE_UNLOCKED or value == STATE_LOCKED or value == STATE_CONTENDED;
    }

    pub fn validate(self: *const PMutex) !void {
        if (self.magic != PMUTEX_MAGIC) return error.InvalidLock;
        if (self.version != LOCK_VERSION) return error.UnsupportedVersion;
        if (self.layout_padding0 != 0) return error.CorruptLock;
        if (self.checksum.load(.acquire) != CHECKSUM_VALUE) return error.CorruptLock;
        if (!reservedAllZero(self.reserved[0..])) return error.CorruptLock;
        if (!validState(self.state.load(.acquire))) return error.CorruptLock;
    }

    pub fn isOwnedByCurrentThread(self: *const PMutex) bool {
        const tid = currentThreadIdU64();
        return self.state.load(.acquire) != STATE_UNLOCKED and self.owner.load(.acquire) == tid;
    }

    pub fn lock(self: *PMutex) !void {
        try self.validate();

        const tid = currentThreadIdU64();
        if (self.owner.load(.acquire) == tid and self.state.load(.acquire) != STATE_UNLOCKED) {
            return error.Deadlock;
        }

        if (tsc.is_simulation) {
            while (self.state.cmpxchgStrong(STATE_UNLOCKED, STATE_LOCKED, .acquire, .monotonic) != null) {
                FiberScheduler.yield();
            }
            self.owner.store(tid, .release);
            return;
        }

        const spin_limit = boundedSpinCount(self.spin_count.load(.acquire));
        var spins: u32 = 0;
        while (spins < spin_limit and self.waiters.load(.acquire) == 0) : (spins += 1) {
            if (self.state.cmpxchgStrong(
                STATE_UNLOCKED,
                STATE_LOCKED,
                .acquire,
                .monotonic,
            ) == null) {
                self.owner.store(tid, .release);
                return;
            }
            std.atomic.spinLoopHint();
        }

        try incrementCounter(&self.waiters, std.math.maxInt(u32));
        var counted = true;
        errdefer {
            if (counted) decrementCounter(&self.waiters);
        }

        while (true) {
            const current = self.state.load(.acquire);
            switch (current) {
                STATE_UNLOCKED => {
                    if (self.state.cmpxchgStrong(
                        STATE_UNLOCKED,
                        STATE_CONTENDED,
                        .acquire,
                        .monotonic,
                    ) == null) {
                        decrementCounter(&self.waiters);
                        counted = false;
                        self.owner.store(tid, .release);
                        return;
                    }
                },
                STATE_LOCKED => {
                    _ = self.state.cmpxchgStrong(
                        STATE_LOCKED,
                        STATE_CONTENDED,
                        .acquire,
                        .monotonic,
                    );
                },
                STATE_CONTENDED => {
                    std.Thread.Futex.wait(&self.state, STATE_CONTENDED);
                },
                else => return error.CorruptLock,
            }
        }
    }

    pub fn tryLock(self: *PMutex) !bool {
        try self.validate();

        const tid = currentThreadIdU64();
        if (self.owner.load(.acquire) == tid and self.state.load(.acquire) != STATE_UNLOCKED) {
            return error.Deadlock;
        }

        if (self.waiters.load(.acquire) != 0) return false;

        if (self.state.cmpxchgStrong(
            STATE_UNLOCKED,
            STATE_LOCKED,
            .acquire,
            .monotonic,
        ) == null) {
            self.owner.store(tid, .release);
            return true;
        }

        return false;
    }

    pub fn unlock(self: *PMutex) !void {
        try self.validate();

        const tid = currentThreadIdU64();
        const current_state = self.state.load(.acquire);

        if (current_state == STATE_UNLOCKED) return error.NotLocked;
        if (self.owner.load(.acquire) != tid) return error.NotOwner;

        const old_state = self.state.swap(STATE_UNLOCKED, .release);
        if (old_state == STATE_UNLOCKED) return error.NotLocked;
        if (!validState(old_state)) return error.CorruptLock;

        _ = self.owner.cmpxchgStrong(tid, 0, .release, .monotonic);

        if (!tsc.is_simulation) {
            if (old_state == STATE_CONTENDED or self.waiters.load(.acquire) != 0) {
                std.Thread.Futex.wake(&self.state, 1);
            }
        }
    }

    pub fn isLocked(self: *const PMutex) bool {
        self.validate() catch return false;
        return self.state.load(.acquire) != STATE_UNLOCKED;
    }

    pub fn getOwner(self: *const PMutex) u64 {
        self.validate() catch return 0;
        if (self.state.load(.acquire) == STATE_UNLOCKED) return 0;
        return self.owner.load(.acquire);
    }

    pub fn getWaiterCount(self: *const PMutex) u32 {
        self.validate() catch return 0;
        return self.waiters.load(.acquire);
    }

    pub fn setSpinCount(self: *PMutex, value: u32) !void {
        try self.validate();
        self.spin_count.store(boundedSpinCount(value), .release);
    }

    pub fn reset(self: *PMutex) !void {
        const state_value = self.state.load(.acquire);
        const waiter_count = self.waiters.load(.acquire);
        if (state_value != STATE_UNLOCKED or waiter_count != 0) return error.Busy;
        self.* = PMutex.init();
    }
};

pub const PRWLock = extern struct {
    magic: u32,
    version: u32,
    readers: atomic.Value(u32),
    layout_padding0: u32,
    writer: atomic.Value(u64),
    write_waiters: atomic.Value(u32),
    read_waiters: atomic.Value(u32),
    state: atomic.Value(u32),
    checksum: atomic.Value(u32),
    reserved: [32]u8,

    const RW_READER_MASK: u32 = 0x3fffffff;
    const RW_WRITE_WAITING: u32 = 0x40000000;
    const RW_WRITE_LOCKED: u32 = 0x80000000;
    const CHECKSUM_KIND: u32 = 2;
    const CHECKSUM_VALUE: u32 = metadataChecksum(PRWLOCK_MAGIC, LOCK_VERSION, CHECKSUM_KIND, 32);

    pub fn init() PRWLock {
        return PRWLock{
            .magic = PRWLOCK_MAGIC,
            .version = LOCK_VERSION,
            .readers = atomic.Value(u32).init(0),
            .layout_padding0 = 0,
            .writer = atomic.Value(u64).init(0),
            .write_waiters = atomic.Value(u32).init(0),
            .read_waiters = atomic.Value(u32).init(0),
            .state = atomic.Value(u32).init(0),
            .checksum = atomic.Value(u32).init(CHECKSUM_VALUE),
            .reserved = [_]u8{0} ** 32,
        };
    }

    pub fn validate(self: *const PRWLock) !void {
        if (self.magic != PRWLOCK_MAGIC) return error.InvalidLock;
        if (self.version != LOCK_VERSION) return error.UnsupportedVersion;
        if (self.layout_padding0 != 0) return error.CorruptLock;
        if (self.checksum.load(.acquire) != CHECKSUM_VALUE) return error.CorruptLock;
        if (!reservedAllZero(self.reserved[0..])) return error.CorruptLock;

        const s = self.state.load(.acquire);
        const reader_count = s & RW_READER_MASK;
        const write_locked = (s & RW_WRITE_LOCKED) != 0;
        if (write_locked and reader_count != 0) return error.CorruptLock;
    }

    fn readerCountFromState(value: u32) u32 {
        return value & RW_READER_MASK;
    }

    fn canRead(self: *PRWLock, state_value: u32) bool {
        if ((state_value & RW_WRITE_LOCKED) != 0) return false;
        if ((state_value & RW_WRITE_WAITING) == 0 and self.write_waiters.load(.acquire) == 0) return true;
        return readerTrackCount(@intFromPtr(self)) != 0;
    }

    fn undoReadAcquire(self: *PRWLock) void {
        while (true) {
            const s = self.state.load(.acquire);
            const rc = readerCountFromState(s);
            std.debug.assert(rc > 0);
            const new_state = s - 1;
            if (self.state.cmpxchgWeak(s, new_state, .release, .monotonic) == null) {
                _ = self.readers.fetchSub(1, .acq_rel);
                if (!tsc.is_simulation and rc == 1 and self.write_waiters.load(.acquire) != 0) {
                    std.Thread.Futex.wake(&self.state, 1);
                }
                return;
            }
        }
    }

    pub fn lockRead(self: *PRWLock) !void {
        try self.validate();

        const tid = currentThreadIdU64();
        if (self.writer.load(.acquire) == tid and (self.state.load(.acquire) & RW_WRITE_LOCKED) != 0) {
            return error.Deadlock;
        }

        while (true) {
            const current_state = self.state.load(.acquire);
            const current_readers = readerCountFromState(current_state);

            if (self.canRead(current_state)) {
                if (current_readers == RW_READER_MASK) return error.TooManyReaders;
                if (self.state.cmpxchgWeak(
                    current_state,
                    current_state + 1,
                    .acquire,
                    .monotonic,
                ) == null) {
                    _ = self.readers.fetchAdd(1, .acq_rel);
                    readerTrackAdd(@intFromPtr(self)) catch |err| {
                        self.undoReadAcquire();
                        return err;
                    };
                    return;
                }
                continue;
            }

            if (tsc.is_simulation) {
                FiberScheduler.yield();
                continue;
            }

            try incrementCounter(&self.read_waiters, std.math.maxInt(u32));
            var counted = true;
            defer {
                if (counted) decrementCounter(&self.read_waiters);
            }

            while (true) {
                const wait_state = self.state.load(.acquire);
                if (self.canRead(wait_state)) break;
                std.Thread.Futex.wait(&self.state, wait_state);
            }

            decrementCounter(&self.read_waiters);
            counted = false;
        }
    }

    pub fn tryLockRead(self: *PRWLock) !bool {
        try self.validate();

        const tid = currentThreadIdU64();
        if (self.writer.load(.acquire) == tid and (self.state.load(.acquire) & RW_WRITE_LOCKED) != 0) {
            return error.Deadlock;
        }

        const current_state = self.state.load(.acquire);
        const current_readers = readerCountFromState(current_state);
        if (!self.canRead(current_state)) return false;
        if (current_readers == RW_READER_MASK) return error.TooManyReaders;

        if (self.state.cmpxchgStrong(
            current_state,
            current_state + 1,
            .acquire,
            .monotonic,
        ) == null) {
            _ = self.readers.fetchAdd(1, .acq_rel);
            readerTrackAdd(@intFromPtr(self)) catch |err| {
                self.undoReadAcquire();
                return err;
            };
            return true;
        }

        return false;
    }

    pub fn unlockRead(self: *PRWLock) !void {
        try self.validate();

        if (readerTrackCount(@intFromPtr(self)) == 0) return error.NotOwner;

        var old_reader_count: u32 = 0;
        while (true) {
            const current_state = self.state.load(.acquire);
            old_reader_count = readerCountFromState(current_state);
            if (old_reader_count == 0) return error.NotLocked;
            const new_state = current_state - 1;
            if (self.state.cmpxchgWeak(
                current_state,
                new_state,
                .release,
                .monotonic,
            ) == null) {
                break;
            }
        }

        _ = self.readers.fetchSub(1, .acq_rel);
        try readerTrackRemove(@intFromPtr(self));

        if (!tsc.is_simulation and old_reader_count == 1) {
            if (self.write_waiters.load(.acquire) > 0) {
                std.Thread.Futex.wake(&self.state, 1);
            } else if (self.read_waiters.load(.acquire) > 0) {
                wakeAll(&self.state);
            }
        }
    }

    fn setWriteWaiting(self: *PRWLock) !void {
        while (true) {
            const s = self.state.load(.acquire);
            if ((s & RW_WRITE_WAITING) != 0) return;
            const new_state = s | RW_WRITE_WAITING;
            if (self.state.cmpxchgWeak(s, new_state, .acquire, .monotonic) == null) return;
        }
    }

    pub fn lockWrite(self: *PRWLock) !void {
        try self.validate();

        const tid = currentThreadIdU64();
        if (self.writer.load(.acquire) == tid and (self.state.load(.acquire) & RW_WRITE_LOCKED) != 0) {
            return error.Deadlock;
        }
        if (readerTrackCount(@intFromPtr(self)) != 0) {
            return error.Deadlock;
        }

        if (self.state.cmpxchgStrong(
            0,
            RW_WRITE_LOCKED,
            .acquire,
            .monotonic,
        ) == null) {
            self.writer.store(tid, .release);
            return;
        }

        if (tsc.is_simulation) {
            while (true) {
                const current_state = self.state.load(.acquire);
                const active_bits = current_state & (RW_WRITE_LOCKED | RW_READER_MASK);
                if (active_bits == 0) {
                    if (self.state.cmpxchgStrong(current_state, RW_WRITE_LOCKED, .acquire, .monotonic) == null) {
                        self.writer.store(tid, .release);
                        return;
                    }
                }
                FiberScheduler.yield();
            }
        }

        try incrementCounter(&self.write_waiters, std.math.maxInt(u32));
        var counted = true;
        errdefer {
            if (counted) decrementCounter(&self.write_waiters);
        }

        try self.setWriteWaiting();

        while (true) {
            const current_state = self.state.load(.acquire);
            const active_bits = current_state & (RW_WRITE_LOCKED | RW_READER_MASK);

            if (active_bits == 0) {
                const waiter_count = self.write_waiters.load(.acquire);
                const new_state: u32 = RW_WRITE_LOCKED | if (waiter_count > 1) RW_WRITE_WAITING else 0;
                if (self.state.cmpxchgStrong(
                    current_state,
                    new_state,
                    .acquire,
                    .monotonic,
                ) == null) {
                    decrementCounter(&self.write_waiters);
                    counted = false;
                    self.writer.store(tid, .release);
                    return;
                }
                continue;
            }

            std.Thread.Futex.wait(&self.state, current_state);
        }
    }

    pub fn tryLockWrite(self: *PRWLock) !bool {
        try self.validate();

        const tid = currentThreadIdU64();
        if (self.writer.load(.acquire) == tid and (self.state.load(.acquire) & RW_WRITE_LOCKED) != 0) {
            return error.Deadlock;
        }
        if (readerTrackCount(@intFromPtr(self)) != 0) {
            return error.Deadlock;
        }

        if (self.state.cmpxchgStrong(
            0,
            RW_WRITE_LOCKED,
            .acquire,
            .monotonic,
        ) == null) {
            self.writer.store(tid, .release);
            return true;
        }

        return false;
    }

    pub fn unlockWrite(self: *PRWLock) !void {
        try self.validate();

        const tid = currentThreadIdU64();
        if (self.writer.load(.acquire) != tid) return error.NotOwner;

        while (true) {
            const current_state = self.state.load(.acquire);
            if ((current_state & RW_WRITE_LOCKED) == 0) return error.NotLocked;

            const writer_waiters = self.write_waiters.load(.acquire);
            const new_state: u32 = if (writer_waiters > 0) RW_WRITE_WAITING else 0;

            if (self.state.cmpxchgStrong(
                current_state,
                new_state,
                .release,
                .monotonic,
            ) == null) {
                break;
            }
        }

        _ = self.writer.cmpxchgStrong(tid, 0, .release, .monotonic);

        if (!tsc.is_simulation) {
            if (self.write_waiters.load(.acquire) > 0) {
                std.Thread.Futex.wake(&self.state, 1);
            } else if (self.read_waiters.load(.acquire) > 0) {
                wakeAll(&self.state);
            }
        }
    }

    pub fn isWriteLocked(self: *const PRWLock) bool {
        self.validate() catch return false;
        return (self.state.load(.acquire) & RW_WRITE_LOCKED) != 0 and self.writer.load(.acquire) != 0;
    }

    pub fn getReaderCount(self: *const PRWLock) u32 {
        self.validate() catch return 0;
        return readerCountFromState(self.state.load(.acquire));
    }

    pub fn getWriteWaiterCount(self: *const PRWLock) u32 {
        self.validate() catch return 0;
        return self.write_waiters.load(.acquire);
    }

    pub fn getReadWaiterCount(self: *const PRWLock) u32 {
        self.validate() catch return 0;
        return self.read_waiters.load(.acquire);
    }

    pub fn reset(self: *PRWLock) !void {
        if ((self.state.load(.acquire) & (RW_WRITE_LOCKED | RW_READER_MASK)) != 0) return error.Busy;
        if (self.write_waiters.load(.acquire) != 0) return error.Busy;
        if (self.read_waiters.load(.acquire) != 0) return error.Busy;
        self.* = PRWLock.init();
    }
};

pub const PCondVar = extern struct {
    magic: u32,
    version: u32,
    waiters: atomic.Value(u32),
    signals: atomic.Value(u32),
    generation: atomic.Value(u32),
    layout_padding0: u32,
    mutex_addr: atomic.Value(usize),
    checksum: atomic.Value(u32),
    reserved: [32]u8,

    const CHECKSUM_KIND: u32 = 3;
    const CHECKSUM_VALUE: u32 = metadataChecksum(PCONDVAR_MAGIC, LOCK_VERSION, CHECKSUM_KIND, 32);

    pub fn init() PCondVar {
        return PCondVar{
            .magic = PCONDVAR_MAGIC,
            .version = LOCK_VERSION,
            .waiters = atomic.Value(u32).init(0),
            .signals = atomic.Value(u32).init(0),
            .generation = atomic.Value(u32).init(0),
            .layout_padding0 = 0,
            .mutex_addr = atomic.Value(usize).init(0),
            .checksum = atomic.Value(u32).init(CHECKSUM_VALUE),
            .reserved = [_]u8{0} ** 32,
        };
    }

    pub fn validate(self: *const PCondVar) !void {
        if (self.magic != PCONDVAR_MAGIC) return error.InvalidCondVar;
        if (self.version != LOCK_VERSION) return error.UnsupportedVersion;
        if (self.layout_padding0 != 0) return error.CorruptCondVar;
        if (self.checksum.load(.acquire) != CHECKSUM_VALUE) return error.CorruptCondVar;
        if (!reservedAllZero(self.reserved[0..])) return error.CorruptCondVar;
    }

    fn bindMutex(self: *PCondVar, mutex: *PMutex) !void {
        const addr = @intFromPtr(mutex);
        while (true) {
            const old = self.mutex_addr.load(.acquire);
            if (old == addr) return;
            if (old != 0) return error.InvalidMutex;
            if (self.mutex_addr.cmpxchgStrong(0, addr, .acq_rel, .monotonic) == null) return;
        }
    }

    fn addSignalPermit(self: *PCondVar, permits: u32) bool {
        if (permits == 0) return false;

        while (true) {
            const waiter_count = self.waiters.load(.acquire);
            const signal_count = self.signals.load(.acquire);
            if (waiter_count == 0 or signal_count >= waiter_count) return false;

            const available = waiter_count - signal_count;
            const to_add = @min(available, permits);

            if (self.signals.cmpxchgWeak(
                signal_count,
                signal_count + to_add,
                .acq_rel,
                .monotonic,
            ) == null) {
                return true;
            }
        }
    }

    pub fn wait(self: *PCondVar, mutex: *PMutex) !void {
        try self.validate();
        try mutex.validate();
        try self.bindMutex(mutex);

        if (!mutex.isOwnedByCurrentThread()) return error.NotOwner;

        try incrementCounter(&self.waiters, std.math.maxInt(u32));
        var counted = true;
        defer {
            if (counted) decrementCounter(&self.waiters);
        }

        try mutex.unlock();

        while (true) {
            while (true) {
                const signal_count = self.signals.load(.acquire);
                if (signal_count == 0) break;
                if (self.signals.cmpxchgWeak(
                    signal_count,
                    signal_count - 1,
                    .acquire,
                    .monotonic,
                ) == null) {
                    try mutex.lock();
                    decrementCounter(&self.waiters);
                    counted = false;
                    return;
                }
            }

            if (tsc.is_simulation) {
                FiberScheduler.yield();
                continue;
            }

            const observed_generation = self.generation.load(.acquire);
            std.Thread.Futex.wait(&self.generation, observed_generation);
        }
    }

    pub fn signal(self: *PCondVar) !void {
        try self.validate();

        if (!self.addSignalPermit(1)) return;

        _ = self.generation.fetchAdd(1, .release);
        if (!tsc.is_simulation) std.Thread.Futex.wake(&self.generation, 1);
    }

    pub fn broadcast(self: *PCondVar) !void {
        try self.validate();

        const waiter_count = self.waiters.load(.acquire);
        if (waiter_count == 0) return;

        if (!self.addSignalPermit(waiter_count)) return;

        _ = self.generation.fetchAdd(1, .release);
        if (!tsc.is_simulation) wakeAll(&self.generation);
    }

    pub fn getWaiterCount(self: *const PCondVar) u32 {
        self.validate() catch return 0;
        return self.waiters.load(.acquire);
    }

    pub fn getSignalCount(self: *const PCondVar) u32 {
        self.validate() catch return 0;
        return self.signals.load(.acquire);
    }

    pub fn reset(self: *PCondVar) !void {
        if (self.waiters.load(.acquire) != 0) return error.Busy;
        self.* = PCondVar.init();
    }
};

pub const Semaphore = struct {
    value: atomic.Value(u32),
    max: u32,
    waiters: atomic.Value(u32),
    magic: u32,

    pub fn init(initial: u32, max_val: u32) !Semaphore {
        if (initial > max_val) return error.InvalidSemaphore;
        return Semaphore{
            .value = atomic.Value(u32).init(initial),
            .max = max_val,
            .waiters = atomic.Value(u32).init(0),
            .magic = 0x53454D41,
        };
    }

    fn validate(self: *const Semaphore) !void {
        if (self.magic != 0x53454D41) return error.InvalidSemaphore;
        if (self.value.load(.acquire) > self.max) return error.InvalidSemaphore;
    }

    pub fn wait(self: *Semaphore) !void {
        try self.validate();

        var failed_attempts: u32 = 0;

        while (true) {
            const current = self.value.load(.acquire);
            if (current != 0) {
                if (self.value.cmpxchgWeak(
                    current,
                    current - 1,
                    .acquire,
                    .monotonic,
                ) == null) {
                    return;
                }

                failed_attempts += 1;
                if (failed_attempts > 64) {
                    failed_attempts = 0;
                    if (tsc.is_simulation) FiberScheduler.yield() else std.Thread.yield() catch {};
                } else {
                    std.atomic.spinLoopHint();
                }
                continue;
            }

            if (tsc.is_simulation) {
                FiberScheduler.yield();
                continue;
            }

            try incrementCounter(&self.waiters, std.math.maxInt(u32));
            var counted = true;
            defer {
                if (counted) decrementCounter(&self.waiters);
            }

            while (self.value.load(.acquire) == 0) {
                std.Thread.Futex.wait(&self.value, 0);
            }

            decrementCounter(&self.waiters);
            counted = false;
        }
    }

    pub fn tryWait(self: *Semaphore) !bool {
        try self.validate();

        var failed_attempts: u32 = 0;

        while (true) {
            const current = self.value.load(.acquire);
            if (current == 0) return false;

            if (self.value.cmpxchgWeak(
                current,
                current - 1,
                .acquire,
                .monotonic,
            ) == null) {
                return true;
            }

            failed_attempts += 1;
            if (failed_attempts > 64) {
                return false;
            }
            std.atomic.spinLoopHint();
        }
    }

    pub fn post(self: *Semaphore) !void {
        try self.validate();

        while (true) {
            const current = self.value.load(.acquire);
            if (current >= self.max) return error.SemaphoreOverflow;

            if (self.value.cmpxchgWeak(
                current,
                current + 1,
                .release,
                .monotonic,
            ) == null) {
                if (!tsc.is_simulation and self.waiters.load(.acquire) != 0) {
                    std.Thread.Futex.wake(&self.value, 1);
                }
                return;
            }
        }
    }

    pub fn getValue(self: *const Semaphore) u32 {
        self.validate() catch return 0;
        return self.value.load(.acquire);
    }

    pub fn getWaiterCount(self: *const Semaphore) u32 {
        self.validate() catch return 0;
        return self.waiters.load(.acquire);
    }
};

pub const SpinLock = struct {
    locked: atomic.Value(bool),
    owner: atomic.Value(u64),
    spin_count: atomic.Value(u32),

    pub fn init() SpinLock {
        return SpinLock{
            .locked = atomic.Value(bool).init(false),
            .owner = atomic.Value(u64).init(0),
            .spin_count = atomic.Value(u32).init(DEFAULT_SPIN_COUNT),
        };
    }

    pub fn lock(self: *SpinLock) !void {
        const tid = currentThreadIdU64();
        if (self.owner.load(.acquire) == tid and self.locked.load(.acquire)) {
            return error.Deadlock;
        }

        var spins: u32 = 0;
        var yields: u32 = 0;
        const spin_limit = boundedSpinCount(self.spin_count.load(.acquire));

        while (true) {
            if (self.locked.cmpxchgWeak(
                false,
                true,
                .acquire,
                .monotonic,
            ) == null) {
                self.owner.store(tid, .release);
                return;
            }

            if (self.owner.load(.acquire) == tid) return error.Deadlock;

            if (spins < spin_limit) {
                spins += 1;
                std.atomic.spinLoopHint();
            } else {
                yields += 1;
                if (yields > 1024) return error.WouldBlock;
                if (tsc.is_simulation) FiberScheduler.yield() else std.Thread.yield() catch {};
            }
        }
    }

    pub fn tryLock(self: *SpinLock) !bool {
        const tid = currentThreadIdU64();
        if (self.owner.load(.acquire) == tid and self.locked.load(.acquire)) {
            return error.Deadlock;
        }

        if (self.locked.cmpxchgStrong(
            false,
            true,
            .acquire,
            .monotonic,
        ) == null) {
            self.owner.store(tid, .release);
            return true;
        }

        return false;
    }

    pub fn unlock(self: *SpinLock) !void {
        const tid = currentThreadIdU64();
        if (!self.locked.load(.acquire)) return error.NotLocked;
        if (self.owner.load(.acquire) != tid) return error.NotOwner;

        self.locked.store(false, .release);
        _ = self.owner.cmpxchgStrong(tid, 0, .release, .monotonic);
    }

    pub fn isLocked(self: *const SpinLock) bool {
        return self.locked.load(.acquire);
    }

    pub fn getOwner(self: *const SpinLock) u64 {
        if (!self.locked.load(.acquire)) return 0;
        return self.owner.load(.acquire);
    }
};

pub const LockGuard = struct {
    mutex: ?*PMutex,
    token: u64,

    pub fn init(mutex: *PMutex) !LockGuard {
        try mutex.lock();
        errdefer mutex.unlock() catch {};

        const token = try registerGuard(.mutex);
        return LockGuard{
            .mutex = mutex,
            .token = token,
        };
    }

    pub fn release(self: *LockGuard) !void {
        const mutex = self.mutex orelse return;
        const token = self.token;

        self.mutex = null;
        self.token = 0;

        if (unregisterGuard(token, .mutex)) {
            try mutex.unlock();
        }
    }

    pub fn deinit(self: *LockGuard) void {
        self.release() catch {};
    }
};

pub const ReadGuard = struct {
    lock: ?*PRWLock,
    token: u64,

    pub fn init(lock: *PRWLock) !ReadGuard {
        try lock.lockRead();
        errdefer lock.unlockRead() catch {};

        const token = try registerGuard(.read);
        return ReadGuard{
            .lock = lock,
            .token = token,
        };
    }

    pub fn release(self: *ReadGuard) !void {
        const lock = self.lock orelse return;
        const token = self.token;

        self.lock = null;
        self.token = 0;

        if (unregisterGuard(token, .read)) {
            try lock.unlockRead();
        }
    }

    pub fn deinit(self: *ReadGuard) void {
        self.release() catch {};
    }
};

pub const WriteGuard = struct {
    lock: ?*PRWLock,
    token: u64,

    pub fn init(lock: *PRWLock) !WriteGuard {
        try lock.lockWrite();
        errdefer lock.unlockWrite() catch {};

        const token = try registerGuard(.write);
        return WriteGuard{
            .lock = lock,
            .token = token,
        };
    }

    pub fn release(self: *WriteGuard) !void {
        const lock = self.lock orelse return;
        const token = self.token;

        self.lock = null;
        self.token = 0;

        if (unregisterGuard(token, .write)) {
            try lock.unlockWrite();
        }
    }

    pub fn deinit(self: *WriteGuard) void {
        self.release() catch {};
    }
};

var fiber_thread_list: std.ArrayList(std.Thread) = undefined;
var fiber_thread_list_mutex: std.Thread.Mutex = .{};
var fiber_current_id: atomic.Value(u64) = atomic.Value(u64).init(0);
var fiber_scheduler_initialized: bool = false;

pub const FiberScheduler = struct {
    const FiberWrapper = struct {
        func: *const fn (*anyopaque) void,
        arg: *anyopaque,

        fn run(self: @This()) void {
            self.func(self.arg);
        }
    };

    pub fn init(allocator: std.mem.Allocator) void {
        fiber_thread_list = std.ArrayList(std.Thread).init(allocator);
        fiber_scheduler_initialized = true;
    }

    pub fn deinit() void {
        if (!fiber_scheduler_initialized) return;
        fiber_thread_list.deinit();
        fiber_scheduler_initialized = false;
    }

    pub fn spawn(func: *const fn (*anyopaque) void, arg: *anyopaque) !void {
        const w = FiberWrapper{ .func = func, .arg = arg };
        const thread = try std.Thread.spawn(.{}, FiberWrapper.run, .{w});
        fiber_thread_list_mutex.lock();
        defer fiber_thread_list_mutex.unlock();
        try fiber_thread_list.append(thread);
    }

    pub fn yield() void {
        if (!tsc.is_simulation) return;
        std.Thread.yield() catch {};
    }

    pub fn run() void {
        fiber_thread_list_mutex.lock();
        const items = fiber_thread_list.items;
        for (items) |thread| {
            thread.join();
        }
        fiber_thread_list.clearRetainingCapacity();
        fiber_thread_list_mutex.unlock();
    }

    pub fn currentId() u64 {
        return @as(u64, @intCast(std.Thread.getCurrentId()));
    }
};

pub const FaultKind = enum {
    disk_write,
    power_off,
    corruption,
    network,
    memory,
};

var dst_fault_rate: f32 = 0.01;
var dst_fault_mutex: std.Thread.Mutex = .{};

pub const DSTCoordinator = struct {
    _unused: u8 = 0,

    pub fn init(_: std.mem.Allocator, seed: u64) DSTCoordinator {
        tsc.initSimulation(seed);
        dst_fault_rate = 0.01;
        return .{};
    }

    pub fn deinit(_: *DSTCoordinator) void {}

    pub fn setFaultRate(_: *DSTCoordinator, rate: f32) void {
        dst_fault_mutex.lock();
        defer dst_fault_mutex.unlock();
        dst_fault_rate = rate;
    }

    pub fn checkFault(_: *DSTCoordinator, _: FaultKind) bool {
        if (!tsc.is_simulation) return false;
        dst_fault_mutex.lock();
        defer dst_fault_mutex.unlock();
        const r = tsc.sim_prng.random().float(f32);
        return r < dst_fault_rate;
    }

    pub fn injectFault() void {
        if (!tsc.is_simulation) return;
        dst_fault_mutex.lock();
        defer dst_fault_mutex.unlock();
        _ = tsc.sim_prng.random().float(f32);
    }

    pub fn checkFaultErr() !void {
        if (!tsc.is_simulation) return;
        dst_fault_mutex.lock();
        defer dst_fault_mutex.unlock();
        if (tsc.sim_prng.random().float(f32) < dst_fault_rate) {
            return error.SimulatedFault;
        }
    }
};

test "pmutex basic lock unlock" {
    const testing = std.testing;
    var mutex = PMutex.init();
    try mutex.lock();
    try testing.expect(mutex.isLocked());
    try testing.expectEqual(currentThreadIdU64(), mutex.getOwner());
    try mutex.unlock();
    try testing.expect(!mutex.isLocked());
}

test "pmutex deadlock detection" {
    const testing = std.testing;
    var mutex = PMutex.init();
    try mutex.lock();
    try testing.expectError(error.Deadlock, mutex.lock());
    try mutex.unlock();
}

test "pmutex try lock" {
    const testing = std.testing;
    var mutex = PMutex.init();
    try testing.expect(try mutex.tryLock());
    try testing.expect(!try mutex.tryLock());
    try mutex.unlock();
}

test "pmutex reset" {
    const testing = std.testing;
    var mutex = PMutex.init();
    try mutex.reset();
    try testing.expect(!mutex.isLocked());
}

test "prwlock read and write" {
    const testing = std.testing;
    var rwlock = PRWLock.init();
    try rwlock.lockRead();
    try testing.expectEqual(@as(u32, 1), rwlock.getReaderCount());
    try rwlock.unlockRead();
    try testing.expectEqual(@as(u32, 0), rwlock.getReaderCount());
    try rwlock.lockWrite();
    try testing.expect(rwlock.isWriteLocked());
    try rwlock.unlockWrite();
    try testing.expect(!rwlock.isWriteLocked());
}

test "prwlock deadlock detection" {
    const testing = std.testing;
    var rwlock = PRWLock.init();
    try rwlock.lockWrite();
    try testing.expectError(error.Deadlock, rwlock.lockWrite());
    try rwlock.unlockWrite();
}

test "condvar basic" {
    const testing = std.testing;

    const Context = struct {
        mutex: PMutex = PMutex.init(),
        cond: PCondVar = PCondVar.init(),
        ready: atomic.Value(bool) = atomic.Value(bool).init(false),
        done: atomic.Value(bool) = atomic.Value(bool).init(false),

        fn worker(ctx: *@This()) !void {
            try ctx.mutex.lock();
            defer ctx.mutex.unlock() catch unreachable;

            ctx.ready.store(true, .release);
            while (!ctx.done.load(.acquire)) {
                try ctx.cond.wait(&ctx.mutex);
            }
        }
    };

    var ctx = Context{};
    const thread = try std.Thread.spawn(.{}, Context.worker, .{&ctx});

    while (!ctx.ready.load(.acquire)) {
        std.atomic.spinLoopHint();
    }

    try ctx.mutex.lock();
    ctx.done.store(true, .release);
    try ctx.cond.signal();
    try ctx.mutex.unlock();

    thread.join();

    try testing.expect(ctx.done.load(.acquire));
}

test "semaphore operations" {
    const testing = std.testing;
    var semaphore = try Semaphore.init(1, 2);

    try testing.expectEqual(@as(u32, 1), semaphore.getValue());
    try semaphore.wait();
    try testing.expectEqual(@as(u32, 0), semaphore.getValue());
    try testing.expect(!(try semaphore.tryWait()));
    try semaphore.post();
    try testing.expectEqual(@as(u32, 1), semaphore.getValue());
    try testing.expect(try semaphore.tryWait());
    try semaphore.post();
    try semaphore.post();
    try testing.expectError(error.SemaphoreOverflow, semaphore.post());
}

test "spinlock operations" {
    const testing = std.testing;
    var spinlock = SpinLock.init();

    try spinlock.lock();
    try testing.expect(spinlock.isLocked());
    try testing.expectEqual(currentThreadIdU64(), spinlock.getOwner());
    try testing.expectError(error.Deadlock, spinlock.tryLock());

    try spinlock.unlock();
    try testing.expect(!spinlock.isLocked());
    try testing.expect(try spinlock.tryLock());
    try spinlock.unlock();
}

test "lock guard idempotent deinit" {
    const testing = std.testing;
    var mutex = PMutex.init();

    var guard = try LockGuard.init(&mutex);
    try testing.expect(mutex.isLocked());
    try guard.release();
    try guard.release();
    try testing.expect(!mutex.isLocked());
}

test "read guard idempotent deinit" {
    const testing = std.testing;
    var rwlock = PRWLock.init();

    var guard = try ReadGuard.init(&rwlock);
    try testing.expectEqual(@as(u32, 1), rwlock.getReaderCount());
    try guard.release();
    try guard.release();
    try testing.expectEqual(@as(u32, 0), rwlock.getReaderCount());
}

test "write guard idempotent deinit" {
    const testing = std.testing;
    var rwlock = PRWLock.init();

    var guard = try WriteGuard.init(&rwlock);
    try testing.expect(rwlock.isWriteLocked());
    try guard.release();
    try guard.release();
    try testing.expect(!rwlock.isWriteLocked());
}

test "metadata validation" {
    const testing = std.testing;

    var mutex = PMutex.init();
    var rwlock = PRWLock.init();
    var cond = PCondVar.init();

    try mutex.validate();
    try rwlock.validate();
    try cond.validate();

    try testing.expectEqual(PMUTEX_MAGIC, mutex.magic);
    try testing.expectEqual(PRWLOCK_MAGIC, rwlock.magic);
    try testing.expectEqual(PCONDVAR_MAGIC, cond.magic);
    try testing.expectEqual(LOCK_VERSION, mutex.version);
    try testing.expectEqual(LOCK_VERSION, rwlock.version);
    try testing.expectEqual(LOCK_VERSION, cond.version);
    try testing.expect(mutex.checksum.load(.acquire) != 0);
    try testing.expect(rwlock.checksum.load(.acquire) != 0);
    try testing.expect(cond.checksum.load(.acquire) != 0);
}

test "fiber scheduler spawn and run" {
    const testing = std.testing;
    tsc.initSimulation(0xDEAD);
    defer {
        tsc.is_simulation = false;
    }

    FiberScheduler.init(testing.allocator);
    defer FiberScheduler.deinit();

    var counter = atomic.Value(u32).init(0);

    const FiberFn = struct {
        fn run(ptr: *anyopaque) void {
            const c: *atomic.Value(u32) = @ptrCast(@alignCast(ptr));
            _ = c.fetchAdd(1, .acq_rel);
            FiberScheduler.yield();
            _ = c.fetchAdd(1, .acq_rel);
        }
    };

    try FiberScheduler.spawn(&FiberFn.run, @ptrCast(&counter));
    try FiberScheduler.spawn(&FiberFn.run, @ptrCast(&counter));

    FiberScheduler.run();

    try testing.expectEqual(@as(u32, 4), counter.load(.acquire));
}

test "dst coordinator fault injection" {
    const testing = std.testing;
    tsc.initSimulation(0xF00D);
    defer {
        tsc.is_simulation = false;
    }

    var dst = DSTCoordinator.init(testing.allocator, 0xF00D);
    defer dst.deinit();

    dst.setFaultRate(1.0);
    try testing.expect(dst.checkFault(.disk_write));

    dst.setFaultRate(0.0);
    try testing.expect(!dst.checkFault(.disk_write));
}
