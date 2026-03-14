#!/usr/bin/env bats

BASE=`dirname $BATS_TEST_DIRNAME`
FLOCK="${GRIND} ${BASE}/flock" # valgrind if you're so inclined
TIME=`which time` # don't use built-in time so we can access output
LOCKFILE=`mktemp -t flock.XXXXXXXXXX`

# Helper: check whether a command was blocked (waited) or ran immediately.
# Uses awk to compare elapsed time against a threshold.
was_blocked() {
	local elapsed="$1"
	# "blocked" means elapsed >= 0.3 seconds
	awk "BEGIN { exit ($elapsed >= 0.3) ? 0 : 1 }"
}

was_immediate() {
	local elapsed="$1"
	# "immediate" means elapsed < 0.3 seconds
	awk "BEGIN { exit ($elapsed < 0.3) ? 0 : 1 }"
}

# Hold a lock in the background and wait for it to be acquired
hold_lock() {
	local flags="${1:-}"
	${FLOCK} ${flags} ${LOCKFILE} sleep 1 &
	sleep 0.2  # ensure background process acquires the lock
}

get_elapsed() {
	${TIME} -p "$@" 2>&1 | awk '/real/ {print $2}'
}

# default uses an exclusive lock
@test "exclusive lock prevents addl exclusive locks" {
	hold_lock
	result=$(get_elapsed ${FLOCK} ${LOCKFILE} true)
	was_blocked "$result"
}

# explicit invocation with -x
@test "-x behaves as exclusive" {
	hold_lock "-x"
	result=$(get_elapsed ${FLOCK} -x ${LOCKFILE} true)
	was_blocked "$result"
}

# explicit invocation with --exclusive
@test "--exclusive behaves as exclusive" {
	hold_lock "--exclusive"
	result=$(get_elapsed ${FLOCK} --exclusive ${LOCKFILE} true)
	was_blocked "$result"
}

# -s uses a shared lock instead of exclusive
@test "-s allows other shared locks" {
	hold_lock "-s"
	result=$(get_elapsed ${FLOCK} -s ${LOCKFILE} true)
	was_immediate "$result"
}
@test "-s prevents exclusive locks" {
	hold_lock "-s"
	result=$(get_elapsed ${FLOCK} ${LOCKFILE} true)
	was_blocked "$result"
}

# --shared uses a shared lock instead of exclusive
@test "--shared allows other shared locks" {
	hold_lock "--shared"
	result=$(get_elapsed ${FLOCK} --shared ${LOCKFILE} true)
	was_immediate "$result"
}
@test "--shared prevents exclusive locks" {
	hold_lock "--shared"
	result=$(get_elapsed ${FLOCK} ${LOCKFILE} true)
	was_blocked "$result"
}

# -o doesn't pass fd to child, how to test?

# -w sec waits for file to become unlocked, failing after timeout
@test "-w runs command if the lock is released" {
	${FLOCK} ${LOCKFILE} sleep 0.3 &
	sleep 0.1
	result=$(${FLOCK} -w 2 ${LOCKFILE} echo run || echo err)
	[ "$result" = run ]
}
@test "-w fails if the lock isn't released in time" {
	hold_lock
	result=$(${FLOCK} -w 0.1 ${LOCKFILE} echo run || echo err)
	[ "$result" = err ]
}
@test "-w fails for zero time" {
	hold_lock
	result=$(${FLOCK} -w 0.0 ${LOCKFILE} echo run || echo err)
	[ "$result" = err ]
}
@test "-w fails for negative time" {
	hold_lock
	result=$(${FLOCK} -w 0.0 ${LOCKFILE} echo run || echo err)
	[ "$result" = err ]
}

# --timeout sec waits for file to become unlocked, failing after timeout
@test "--timeout runs command if the lock is released" {
	${FLOCK} ${LOCKFILE} sleep 0.3 &
	sleep 0.1
	result=$(${FLOCK} --timeout 2 ${LOCKFILE} echo run || echo err)
	[ "$result" = run ]
}
@test "--timeout fails if the lock isn't released in time" {
	hold_lock
	result=$(${FLOCK} --timeout 0.1 ${LOCKFILE} echo run || echo err)
	[ "$result" = err ]
}
@test "--timeout fails for zero time" {
	hold_lock
	result=$(${FLOCK} --timeout 0.0 ${LOCKFILE} echo run || echo err)
	[ "$result" = err ]
}
@test "--timeout fails for negative time" {
	hold_lock
	result=$(${FLOCK} --timeout 0.0 ${LOCKFILE} echo run || echo err)
	[ "$result" = err ]
}

# -n fails immediately if file is locked
@test "-n fails if exclusive lock exists" {
	hold_lock
	result=$(${FLOCK} -n ${LOCKFILE} echo run || echo err)
	[ "$result" = err ]
}
@test "-n fails if shared lock exists" {
	hold_lock "-s"
	result=$(${FLOCK} -n ${LOCKFILE} echo run || echo err)
	[ "$result" = err ]
}
@test "-n succeeds if lock is absent" {
	rm -f ${LOCKFILE}
	result=$(${FLOCK} -n ${LOCKFILE} echo run || echo err)
	[ "$result" = run ]
}

# --nonblock fails immediately if file is locked
@test "--nonblock fails if exclusive lock exists" {
	hold_lock
	result=$(${FLOCK} --nonblock ${LOCKFILE} echo run || echo err)
	[ "$result" = err ]
}
@test "--nonblock fails if shared lock exists" {
	hold_lock "-s"
	result=$(${FLOCK} --nonblock ${LOCKFILE} echo run || echo err)
	[ "$result" = err ]
}
@test "--nonblock succeeds if lock is absent" {
	rm -f ${LOCKFILE}
	result=$(${FLOCK} --nonblock ${LOCKFILE} echo run || echo err)
	[ "$result" = run ]
}

# -u forcebly releases lock
@test "-u unlocks existing exclusive lock" {
	hold_lock
	result=$(get_elapsed ${FLOCK} -u ${LOCKFILE} true)
	was_immediate "$result"
}
@test "-u unlocks existing shared lock" {
	hold_lock "-s"
	result=$(get_elapsed ${FLOCK} -u ${LOCKFILE} true)
	was_immediate "$result"
}

# --unlock forcebly releases lock
@test "--unlock unlocks existing exclusive lock" {
	hold_lock
	result=$(get_elapsed ${FLOCK} --unlock ${LOCKFILE} true)
	was_immediate "$result"
}
@test "--unlock unlocks existing shared lock" {
	hold_lock "-s"
	result=$(get_elapsed ${FLOCK} --unlock ${LOCKFILE} true)
	was_immediate "$result"
}

# Ensure -c may be provided
@test "-c may be provided" {
	result=$(${FLOCK} ${LOCKFILE} -c "echo run")
	[ "$result" = run ]
}

# Ensure -c position correct if provided
@test "-c must be provided after lock args and lockfile" {
	${FLOCK} -c echo 1 ${LOCKFILE} || true
}

# -h/--help should exit 0
@test "-h exits with status 0" {
	run ${FLOCK} -h
	[ "$status" -eq 0 ]
}
@test "--help exits with status 0" {
	run ${FLOCK} --help
	[ "$status" -eq 0 ]
}

# special file types
@test "lock on existing file" {
	touch ${LOCKFILE}
	hold_lock
	result=$(get_elapsed ${FLOCK} ${LOCKFILE} true)
	was_blocked "$result"
}

@test "lock on non-existing file" {
	rm -f ${LOCKFILE}
	${FLOCK} ${LOCKFILE} sleep 1 &
	sleep 0.2
	result=$(get_elapsed ${FLOCK} ${LOCKFILE} true)
	was_blocked "$result"
}

@test "lock on read-only file" {
	touch ${LOCKFILE}
	chmod 444 ${LOCKFILE}
	hold_lock
	result=$(get_elapsed ${FLOCK} ${LOCKFILE} true)
	rm -f ${LOCKFILE}
	was_blocked "$result"
}

@test "lock on write-only file" {
	touch ${LOCKFILE}
	chmod 222 ${LOCKFILE}
	hold_lock
	result=$(get_elapsed ${FLOCK} ${LOCKFILE} true)
	rm -f ${LOCKFILE}
	was_blocked "$result"
}

@test "lock on dir" {
	rm -f ${LOCKFILE}
	mkdir -p ${LOCKFILE}
	${FLOCK} ${LOCKFILE} sleep 1 &
	sleep 0.2
	result=$(get_elapsed ${FLOCK} ${LOCKFILE} true)
	rm -rf ${LOCKFILE}
	was_blocked "$result"
}

# fd mode
@test "lock on file descriptor" {
	(
		${FLOCK} -n 8 || exit 1
		# commands executed under lock ...
		sleep 1
	) 8> ${LOCKFILE} &
	sleep 0.2
	result=$(get_elapsed ${FLOCK} ${LOCKFILE} true)
	was_blocked "$result"
}

@test "lock, then unlock on file descriptor" {
	(
		${FLOCK} -n 8 || exit 1
		# commands executed under lock ...
		sleep 0.5
		${FLOCK} -u 8 || exit 1
		sleep 1
	) 8> ${LOCKFILE} &
	sleep 0.2
	result=$(get_elapsed ${FLOCK} ${LOCKFILE} true)
	# Should be blocked for ~0.5s (until unlock), not ~1.5s (until subshell exit)
	was_blocked "$result"
}
