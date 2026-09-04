#!/bin/bash
set -euo pipefail
set -m

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
root_dir="$(cd -- "$script_dir/.." && pwd -P)"
swift_bin="$(/usr/bin/xcrun --find swift 2>/dev/null || true)"

fail() {
    echo "benchmark-quality.sh: $*" >&2
    exit 1
}

durable_sync() {
    local recorder="${POINTER_BENCHMARK_SYNC_RECORDER:-}"
    if [[ -n "$recorder" ]]; then
        [[ "$recorder" == "$root_dir/"* ]] || fail "sync recorder must belong to the repository"
        [[ ! -L "$recorder" ]] || fail "sync recorder must not be a symlink"
        printf '%s\n' "${1:-sync}" >> "$recorder"
        return
    fi
    sync
}

usage() {
    cat >&2 <<'USAGE'
Usage: benchmark-quality.sh \
  --fixture-profile standard12|dense1000 \
  --baseline-commit-sha <40 lowercase hex> \
  --candidate-commit-sha <40 lowercase hex> \
  --baseline-root <build/<fixture-profile>/baseline> \
  --candidate-root <build/<fixture-profile>/candidate> \
  [--baseline-executable <Pointer executable>] \
  [--candidate-executable <Pointer executable>] \
  --baseline-run-provenance <validated JSON file> \
  --candidate-run-provenance <validated JSON file> \
  --pair-eligibility-file <validated JSON file> \
  --output-dir <performance/<fixture-profile>> \
  [--runner <executable wrapper>] \
  [--publish-hook <test-only executable>] \
  [--post-rename-publish-hook <test-only executable>]
USAGE
}

resolve_path() {
    local value="$1"
    [[ "$value" != *$'\n'* ]] || fail "path cannot contain a newline"
    if [[ "$value" == /* ]]; then
        if [[ "$value" == "/" ]]; then
            printf '/\n'
        else
            printf '%s\n' "${value%/}"
        fi
    else
        printf '%s\n' "$root_dir/${value%/}"
    fi
}

reject_traversal() {
    local value="$1"
    case "$value" in
        ../*|*/../*|*/..|./*|*/./*)
            fail "path traversal is not allowed: $value"
            ;;
    esac
}

canonical_directory() {
    local raw="$1"
    local label="$2"
    local resolved
    resolved="$(resolve_path "$raw")"
    reject_traversal "$resolved"
    [[ -d "$resolved" ]] || fail "$label directory is missing: $resolved"
    [[ ! -L "$resolved" ]] || fail "$label must not be a symlink: $resolved"
    local canonical
    canonical="$(cd -- "$resolved" && pwd -P)"
    [[ "$canonical" == "$resolved" ]] || fail "$label must not use a symlink alias: $resolved"
    printf '%s\n' "$canonical"
}

canonical_file() {
    local raw="$1"
    local label="$2"
    local resolved
    resolved="$(resolve_path "$raw")"
    reject_traversal "$resolved"
    [[ -f "$resolved" ]] || fail "$label file is missing: $resolved"
    [[ ! -L "$resolved" ]] || fail "$label must not be a symlink: $resolved"
    local parent
    parent="$(cd -- "$(dirname -- "$resolved")" && pwd -P)"
    local canonical
    canonical="$parent/$(basename -- "$resolved")"
    [[ "$canonical" == "$resolved" ]] || fail "$label must not use a symlink alias: $resolved"
    [[ -f "$canonical" ]] || fail "$label file is not regular: $canonical"
    printf '%s\n' "$canonical"
}

physical_ancestor() {
    local resolved="$1"
    local label="$2"
    [[ "$resolved" != "/" ]] || fail "$label cannot be the filesystem root"
    local nearest_existing="$resolved"
    while [[ ! -e "$nearest_existing" && ! -L "$nearest_existing" ]]; do
        local next_existing
        next_existing="$(dirname -- "$nearest_existing")"
        [[ "$next_existing" != "$nearest_existing" ]] || fail "$label has no physical ancestor: $resolved"
        nearest_existing="$next_existing"
    done
    [[ -d "$nearest_existing" ]] || fail "$label physical ancestor is not a directory: $nearest_existing"
    [[ ! -L "$nearest_existing" ]] || fail "$label has a symlinked physical ancestor: $nearest_existing"
    local canonical_nearest
    canonical_nearest="$(cd -- "$nearest_existing" && pwd -P)"
    local suffix="${resolved#"$nearest_existing"}"
    local physical_candidate="$canonical_nearest$suffix"
    [[ "$physical_candidate" == "$resolved" ]] || fail "$label must not use a symlink alias: $resolved"
    printf '%s\n' "$canonical_nearest"
}

physical_path() {
    local resolved="$1"
    local label="$2"
    if [[ "$resolved" == "/" ]]; then
        printf '/\n'
        return
    fi
    local nearest_existing="$resolved"
    while [[ ! -e "$nearest_existing" && ! -L "$nearest_existing" ]]; do
        local next_existing
        next_existing="$(dirname -- "$nearest_existing")"
        [[ "$next_existing" != "$nearest_existing" ]] || fail "$label has no physical ancestor: $resolved"
        nearest_existing="$next_existing"
    done
    [[ -d "$nearest_existing" ]] || fail "$label physical ancestor is not a directory: $nearest_existing"
    [[ ! -L "$nearest_existing" ]] || fail "$label has a symlinked physical ancestor: $nearest_existing"
    local canonical_nearest
    canonical_nearest="$(cd -- "$nearest_existing" && pwd -P)"
    local suffix="${resolved#"$nearest_existing"}"
    local physical_candidate="$canonical_nearest$suffix"
    [[ "$physical_candidate" == "$resolved" ]] || fail "$label must not use a symlink alias: $resolved"
    printf '%s\n' "$physical_candidate"
}

canonical_destination() {
    local raw="$1"
    local label="$2"
    local resolved
    resolved="$(resolve_path "$raw")"
    reject_traversal "$resolved"
    [[ "$resolved" != "/" ]] || fail "$label cannot be the filesystem root"

    physical_path "$resolved" "$label" >/dev/null
    local parent
    parent="$(dirname -- "$resolved")"
    local canonical_parent
    canonical_parent="$(physical_path "$parent" "$label parent")"
    local canonical
    canonical="$canonical_parent/$(basename -- "$resolved")"
    [[ "$canonical" == "$resolved" ]] || fail "$label must not use a symlink alias: $resolved"

    if [[ -e "$resolved" || -L "$resolved" ]]; then
        [[ -d "$resolved" ]] || fail "$label must be a directory: $resolved"
        [[ ! -L "$resolved" ]] || fail "$label must not be a symlink: $resolved"
    fi
    printf '%s\n' "$canonical"
}

path_contains() {
    local parent="$1"
    local child="$2"
    [[ "$child" == "$parent" || "$child" == "$parent/"* ]]
}

validate_json_files() {
    [[ -x "$swift_bin" ]] || fail "swift is unavailable for provenance validation"
    if ! "$swift_bin" - "$@" <<'SWIFT'
import Foundation

do {
    for path in CommandLine.arguments.dropFirst() {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              JSONSerialization.isValidJSONObject(object)
        else { throw NSError(domain: "PointerQuality", code: 1) }
    }
} catch {
    fputs("benchmark-quality.sh: invalid JSON input\n", stderr)
    exit(1)
}

SWIFT
    then
        fail "provenance or eligibility JSON validation failed"
    fi
}

validate_physical_directory() {
    local directory="$1"
    local label="$2"
    [[ -d "$directory" ]] || fail "$label directory is missing: $directory"
    [[ ! -L "$directory" ]] || fail "$label must not be a symlink: $directory"
    local canonical
    canonical="$(cd -- "$directory" && pwd -P)"
    [[ "$canonical" == "$directory" ]] || fail "$label must not use a symlink alias: $directory"
}

validate_regular_json_file() {
    local file="$1"
    local label="$2"
    [[ -f "$file" ]] || fail "$label file is missing: $file"
    [[ ! -L "$file" ]] || fail "$label must not be a symlink: $file"
}

validate_exact_entries() {
    local directory="$1"
    local label="$2"
    shift 2
    local actual_count=0
    local entry name expected allowed
    while IFS= read -r -d '' entry; do
        name="$(basename -- "$entry")"
        allowed=false
        for expected in "$@"; do
            if [[ "$name" == "$expected" ]]; then
                allowed=true
                break
            fi
        done
        [[ "$allowed" == true ]] || fail "$label contains an unexpected entry: $entry"
        ((actual_count += 1))
    done < <(find "$directory" -mindepth 1 -maxdepth 1 -print0)
    [[ "$actual_count" -eq "$#" ]] || fail "$label does not contain exactly the expected entries"
    for expected in "$@"; do
        [[ -e "$directory/$expected" || -L "$directory/$expected" ]] || fail "$label is missing: $directory/$expected"
    done
}

validate_staged_output() {
    local staged="$1"
    validate_physical_directory "$staged" "staged profile evidence"
    validate_exact_entries "$staged" "staged profile evidence" comparisons provenance measurements pair-execution

    for directory in comparisons provenance measurements pair-execution; do
        validate_physical_directory "$staged/$directory" "staged $directory"
    done
    validate_exact_entries "$staged/comparisons" "staged comparisons" pair-eligibility.json
    validate_exact_entries "$staged/provenance" "staged provenance" baseline.json candidate.json
    validate_exact_entries "$staged/measurements" "staged measurements" baseline.json candidate.json
    validate_exact_entries "$staged/pair-execution" "staged pair execution" pair-execution.json

    local json_file
    for json_file in \
        "$staged/comparisons/pair-eligibility.json" \
        "$staged/provenance/baseline.json" \
        "$staged/provenance/candidate.json" \
        "$staged/measurements/baseline.json" \
        "$staged/measurements/candidate.json" \
        "$staged/pair-execution/pair-execution.json"; do
        validate_regular_json_file "$json_file" "staged JSON"
    done
    validate_json_files \
        "$staged/comparisons/pair-eligibility.json" \
        "$staged/provenance/baseline.json" \
        "$staged/provenance/candidate.json" \
        "$staged/measurements/baseline.json" \
        "$staged/measurements/candidate.json" \
        "$staged/pair-execution/pair-execution.json"
}

validate_existing_preseed() {
    local existing="$1"
    validate_physical_directory "$existing" "existing profile evidence"
    validate_physical_directory "$existing/comparisons" "existing comparisons"
    validate_exact_entries "$existing/comparisons" "existing comparisons" pair-eligibility.json
    validate_regular_json_file "$existing/comparisons/pair-eligibility.json" "existing eligibility"
    if [[ -e "$existing/provenance" || -L "$existing/provenance" ]]; then
        validate_physical_directory "$existing/provenance" "existing provenance"
        validate_exact_entries "$existing/provenance" "existing provenance" baseline.json candidate.json
        validate_regular_json_file "$existing/provenance/baseline.json" "existing baseline provenance"
        validate_regular_json_file "$existing/provenance/candidate.json" "existing candidate provenance"
        validate_json_files \
            "$existing/provenance/baseline.json" \
            "$existing/provenance/candidate.json"
    fi
    if [[ -e "$existing/measurements" || -L "$existing/measurements" || \
          -e "$existing/pair-execution" || -L "$existing/pair-execution" ]]; then
        fail "existing preseed contains finalized output nodes: $existing"
    fi
    local entry name
    while IFS= read -r -d '' entry; do
        name="$(basename -- "$entry")"
        [[ "$name" == comparisons || "$name" == provenance ]] || fail "existing profile evidence contains an unexpected entry: $entry"
    done < <(find "$existing" -mindepth 1 -maxdepth 1 -print0)
}

write_transaction_journal() {
    local state="$1"
    local temporary="$transaction_journal.tmp"
    [[ "$state" == prepared || "$state" == backed-up || "$state" == installed ]] || fail "invalid transaction state: $state"
    [[ ! -L "$transaction_journal" ]] || fail "transaction journal must not be a symlink: $transaction_journal"
    [[ ! -e "$temporary" || -f "$temporary" ]] || fail "transaction journal temporary path is not a regular file: $temporary"
    [[ ! -L "$temporary" ]] || fail "transaction journal temporary path must not be a symlink: $temporary"
    printf '%s\n' \
        'version=1' \
        "state=$state" \
        "output=$output_dir" \
        "backup=$backup_output" \
        "staging=$staging_parent" \
        "had-existing=$transaction_had_existing" > "$temporary"
    durable_sync journal-file
    mv -f -- "$temporary" "$transaction_journal"
    durable_sync journal-directory
}

recover_pending_transaction() {
    local temporary="$transaction_journal.tmp"
    if [[ ! -e "$transaction_journal" && ! -L "$transaction_journal" ]]; then
        if [[ -e "$temporary" || -L "$temporary" ]]; then
            [[ -f "$temporary" && ! -L "$temporary" ]] || fail "transaction journal temporary path is not a regular file: $temporary"
            rm -f -- "$temporary"
        fi
        [[ ! -e "$backup_parent" && ! -L "$backup_parent" ]] || fail "orphaned transaction backup requires recovery: $backup_parent"
        if [[ -e "$staging_parent" || -L "$staging_parent" ]]; then
            [[ -d "$staging_parent" && ! -L "$staging_parent" ]] || fail "orphaned transaction staging is not a physical directory: $staging_parent"
            [[ -z "$(find "$staging_parent" -mindepth 1 -print -quit)" ]] || fail "orphaned transaction staging requires recovery: $staging_parent"
            rm -rf -- "$staging_parent"
        fi
        if [[ -e "$child_control_dir" || -L "$child_control_dir" ]]; then
            [[ -d "$child_control_dir" && ! -L "$child_control_dir" ]] || fail "orphaned child control is not a physical directory: $child_control_dir"
            [[ -z "$(find "$child_control_dir" -mindepth 1 -print -quit)" ]] || fail "orphaned child control requires recovery: $child_control_dir"
            rm -rf -- "$child_control_dir"
        fi
        return
    fi
    [[ -f "$transaction_journal" && ! -L "$transaction_journal" ]] || fail "transaction journal is not a regular file: $transaction_journal"
    [[ "$(sed -n '1p' "$transaction_journal")" == "version=1" ]] || fail "unsupported transaction journal version"
    local state
    state="$(sed -n '2p' "$transaction_journal")"
    state="${state#state=}"
    [[ "$state" == prepared || "$state" == backed-up || "$state" == installed ]] || fail "invalid transaction journal state"
    [[ "$(sed -n '3p' "$transaction_journal")" == "output=$output_dir" ]] || fail "transaction journal output path does not match"
    [[ "$(sed -n '4p' "$transaction_journal")" == "backup=$backup_output" ]] || fail "transaction journal backup path does not match"
    [[ "$(sed -n '5p' "$transaction_journal")" == "staging=$staging_parent" ]] || fail "transaction journal staging path does not match"
    local had_existing
    had_existing="$(sed -n '6p' "$transaction_journal")"
    had_existing="${had_existing#had-existing=}"
    [[ "$had_existing" == true || "$had_existing" == false ]] || fail "invalid transaction journal existence state"
    [[ -z "$(sed -n '7p' "$transaction_journal")" ]] || fail "transaction journal contains unexpected data"

    if [[ -e "$backup_output" || -L "$backup_output" ]]; then
        [[ -d "$backup_output" && ! -L "$backup_output" ]] || fail "transaction backup is not a physical directory: $backup_output"
        if [[ -e "$output_dir" || -L "$output_dir" ]]; then
            [[ -d "$output_dir" && ! -L "$output_dir" ]] || fail "transaction output is not a physical directory: $output_dir"
            rm -rf -- "$output_dir"
        fi
        mv -- "$backup_output" "$output_dir"
    elif [[ "$had_existing" == true ]]; then
        [[ -d "$output_dir" && ! -L "$output_dir" ]] || fail "transaction lost its existing evidence backup"
    elif [[ "$had_existing" == false && ( -e "$output_dir" || -L "$output_dir" ) ]]; then
        [[ -d "$output_dir" && ! -L "$output_dir" ]] || fail "transaction output is not a physical directory: $output_dir"
        rm -rf -- "$output_dir"
    fi

    if [[ -e "$staging_parent" || -L "$staging_parent" ]]; then
        [[ -d "$staging_parent" && ! -L "$staging_parent" ]] || fail "transaction staging is not a physical directory: $staging_parent"
        rm -rf -- "$staging_parent"
    fi
    if [[ -e "$backup_parent" || -L "$backup_parent" ]]; then
        [[ -d "$backup_parent" && ! -L "$backup_parent" ]] || fail "transaction backup parent is not a physical directory: $backup_parent"
        rm -rf -- "$backup_parent"
    fi
    if [[ -e "$child_control_dir" || -L "$child_control_dir" ]]; then
        [[ -d "$child_control_dir" && ! -L "$child_control_dir" ]] || fail "transaction child control is not a physical directory: $child_control_dir"
        rm -rf -- "$child_control_dir"
    fi
    rm -f -- "$transaction_journal"
    if [[ -e "$temporary" || -L "$temporary" ]]; then
        [[ -f "$temporary" && ! -L "$temporary" ]] || fail "transaction journal temporary path is not a regular file: $temporary"
        rm -f -- "$temporary"
    fi
}

validate_stale_child_entries() {
    local directory="$1"
    local token="$2"
    local label="$3"
    local entry name
    while IFS= read -r -d '' entry; do
        name="$(basename -- "$entry")"
        case "$name" in
            "$token.gate"|"$token.ready")
                [[ -p "$entry" && ! -L "$entry" ]] || fail "$label contains an invalid gate or ready node: $entry"
                ;;
            "$token.owner"|"$token.owner.tmp"|"$token.capability")
                [[ -f "$entry" && ! -L "$entry" ]] || fail "$label contains an invalid regular node: $entry"
                ;;
            "$token.capability.revoked")
                [[ -f "$entry" && ! -L "$entry" ]] || fail "$label contains an invalid revocation node: $entry"
                ;;
            *)
                fail "$label contains an unexpected entry: $entry"
                ;;
        esac
    done < <(find "$directory" -mindepth 1 -maxdepth 1 -print0)
}

validate_revoked_capability_marker() {
    local marker="$1"
    [[ -f "$marker" && ! -L "$marker" ]] || fail "starting child capability revocation is not a regular file: $marker"
    [[ "$(sed -n '1p' "$marker")" == revoked && -z "$(sed -n '2p' "$marker")" ]] || fail "starting child capability revocation is invalid: $marker"
}

recover_stale_starting_child() {
    local lock="$1"
    local old_transaction="$2"
    local token="$3"
    local namespace
    namespace="$(dirname -- "$lock")/.benchmark-quality.children.$fixture_profile.$old_transaction"
    local quarantine="$namespace.revoked.$token"
    local cleanup="$namespace.cleanup.$token"
    local control_dir
    local owner owner_temporary gate ready capability revoked_capability

    if [[ -e "$namespace" || -L "$namespace" ]]; then
        [[ -d "$namespace" && ! -L "$namespace" ]] || fail "starting child control is not a physical directory: $namespace"
        [[ ! -e "$quarantine" && ! -L "$quarantine" && ! -e "$cleanup" && ! -L "$cleanup" ]] || fail "stale starting child has multiple recovery namespaces"
        validate_stale_child_entries "$namespace" "$token" "starting child control"
        capability="$namespace/$token.capability"
        revoked_capability="$capability.revoked"
        if [[ -e "$revoked_capability" || -L "$revoked_capability" ]]; then
            validate_revoked_capability_marker "$revoked_capability"
        else
            printf '%s\n' revoked > "$revoked_capability"
        fi
        durable_sync child-revoke
        if [[ "${POINTER_BENCHMARK_CRASH_AFTER_CHILD_REVOKE:-0}" == 1 ]]; then
            kill -KILL "$$"
        fi
        mv -- "$namespace" "$quarantine"
        durable_sync child-quarantine
        if [[ "${POINTER_BENCHMARK_CRASH_AFTER_CHILD_QUARANTINE:-0}" == 1 ]]; then
            kill -KILL "$$"
        fi
    elif [[ -e "$quarantine" || -L "$quarantine" ]]; then
        [[ ! -e "$cleanup" && ! -L "$cleanup" ]] || fail "stale starting child has both quarantine and cleanup namespaces"
        [[ -d "$quarantine" && ! -L "$quarantine" ]] || fail "stale starting child quarantine is not a physical directory: $quarantine"
    elif [[ -e "$cleanup" || -L "$cleanup" ]]; then
        [[ -d "$cleanup" && ! -L "$cleanup" ]] || fail "stale starting child cleanup is not a physical directory: $cleanup"
    else
        return
    fi

    if [[ -d "$quarantine" ]]; then
        validate_stale_child_entries "$quarantine" "$token" "starting child quarantine"
        capability="$quarantine/$token.capability"
        revoked_capability="$capability.revoked"
        validate_revoked_capability_marker "$revoked_capability"
        mv -- "$quarantine" "$cleanup"
        durable_sync child-cleanup-tombstone
        if [[ "${POINTER_BENCHMARK_CRASH_AFTER_CHILD_CLEANUP_RENAME:-0}" == 1 ]]; then
            kill -KILL "$$"
        fi
    fi

    control_dir="$cleanup"
    validate_stale_child_entries "$control_dir" "$token" "starting child cleanup"
    capability="$control_dir/$token.capability"
    revoked_capability="$capability.revoked"
    if [[ -e "$revoked_capability" || -L "$revoked_capability" ]]; then
        validate_revoked_capability_marker "$revoked_capability"
    fi
    owner="$control_dir/$token.owner"
    owner_temporary="$owner.tmp"
    gate="$control_dir/$token.gate"
    ready="$control_dir/$token.ready"
    if [[ -e "$owner" || -L "$owner" ]]; then
        local owner_token_line owner_pid_line owner_pgid_line
        owner_token_line="$(sed -n '1p' "$owner")"
        owner_pid_line="$(sed -n '2p' "$owner")"
        owner_pgid_line="$(sed -n '3p' "$owner")"
        [[ -z "$(sed -n '4p' "$owner")" ]] || fail "starting child owner record has unexpected contents: $owner"
        local owner_token="${owner_token_line#token=}"
        local owner_pid="${owner_pid_line#pid=}"
        local owner_pgid="${owner_pgid_line#pgid=}"
        [[ "$owner_token_line" == token=* && "$owner_token" == "$token" ]] || fail "starting child owner token does not match: $owner"
        [[ "$owner_pid_line" == pid=* && "$owner_pid" =~ ^[1-9][0-9]*$ ]] || fail "starting child owner PID is invalid: $owner"
        [[ "$owner_pgid_line" == pgid=* && "$owner_pgid" =~ ^[1-9][0-9]*$ && "$owner_pgid" == "$owner_pid" ]] || fail "starting child owner process group is invalid: $owner"
        kill -TERM "$owner_pid" 2>/dev/null || true
        kill -TERM "-$owner_pgid" 2>/dev/null || true
        if ! wait_for_process_group_exit "$owner_pgid"; then
            kill -KILL "$owner_pid" 2>/dev/null || true
            kill -KILL "-$owner_pgid" 2>/dev/null || true
            wait_for_process_group_exit "$owner_pgid" || fail "starting child process group is still live: $owner_pgid"
        fi
    fi
    local file
    for file in "$gate" "$ready" "$owner" "$owner_temporary" "$capability" "$revoked_capability"; do
        if [[ -e "$file" || -L "$file" ]]; then
            rm -f -- "$file"
            durable_sync child-file-removal
            if [[ "$file" == "$revoked_capability" && "${POINTER_BENCHMARK_CRASH_AFTER_CHILD_REVOCATION_REMOVAL:-0}" == 1 ]]; then
                kill -KILL "$$"
            fi
            if [[ "${POINTER_BENCHMARK_CRASH_AFTER_CHILD_FILE_REMOVAL:-0}" == 1 ]]; then
                kill -KILL "$$"
            fi
        fi
    done
    [[ -z "$(find "$control_dir" -mindepth 1 -print -quit)" ]] || fail "starting child cleanup contains unrecoverable contents: $control_dir"
    rmdir -- "$control_dir" || fail "could not remove stale starting child cleanup: $control_dir"
    durable_sync child-cleanup
}

recover_stale_child_namespace() {
    local lock="$1"
    local old_transaction="$2"
    local control_dir
    control_dir="$(dirname -- "$lock")/.benchmark-quality.children.$fixture_profile.$old_transaction"
    if [[ ! -e "$control_dir" && ! -L "$control_dir" ]]; then
        return
    fi
    [[ -d "$control_dir" && ! -L "$control_dir" ]] || fail "stale child control is not a physical directory: $control_dir"
    local entry name
    while IFS= read -r -d '' entry; do
        name="$(basename -- "$entry")"
        case "$name" in
            "$old_transaction"-*.gate|"$old_transaction"-*.ready|"$old_transaction"-*.owner|"$old_transaction"-*.owner.tmp|"$old_transaction"-*.capability|"$old_transaction"-*.capability.revoked) ;;
            *) fail "stale child control contains an unexpected entry: $entry" ;;
        esac
    done < <(find "$control_dir" -mindepth 1 -maxdepth 1 -print0)
    rm -rf -- "$control_dir"
    durable_sync child-namespace-cleanup
}

acquire_profile_lock() {
    local lock="$1"
    [[ -d "$(dirname -- "$lock")" && ! -L "$(dirname -- "$lock")" ]] || fail "profile lock parent is not a physical directory"
    local attempt
    for attempt in 1 2; do
        if ( set -o noclobber; printf '%s\n' \
            'version=1' \
            "pid=$$" \
            "transaction=$transaction_id" \
            'child=none' \
            'child-state=idle' \
            'child-token=none' \
            'child-pgid=none' > "$lock" ) 2>/dev/null; then
            validate_profile_lock_file "$lock" "$$" "$transaction_id" || {
                rm -f -- "$lock"
                fail "profile lock could not be validated after creation"
            }
            profile_lock="$lock"
            profile_lock_acquired=true
            durable_sync lock-create
            return
        fi
        [[ -f "$lock" && ! -L "$lock" ]] || fail "profile lock is not a regular file: $lock"
        validate_profile_lock_file "$lock" || fail "profile lock has invalid contents"
        local owner_pid="$profile_lock_pid"
        local owner_transaction="$profile_lock_transaction"
        local owner_child="$profile_lock_child"
        local owner_state="$profile_lock_child_state"
        local owner_token="$profile_lock_child_token"
        local owner_pgid="$profile_lock_child_pgid"
        validate_profile_lock_child_tuple "$owner_state" "$owner_token" "$owner_child" "$owner_pgid" || fail "profile lock has an invalid child tuple"
        local observed_sha
        observed_sha="$(lock_fingerprint "$lock")"
        [[ "$observed_sha" =~ ^[0-9a-f]{64}$ ]] || fail "could not fingerprint stale profile lock"
        if kill -0 "$owner_pid" 2>/dev/null; then
            fail "profile lock is held by a live process (pid $owner_pid)"
        fi
        if [[ "$owner_child" != none ]] && kill -0 "$owner_child" 2>/dev/null; then
            fail "profile lock is held by a live child process (pid $owner_child)"
        fi
        if [[ "$owner_pgid" != none ]] && kill -0 "-$owner_pgid" 2>/dev/null; then
            fail "profile lock is held by a live child process group (pgid $owner_pgid)"
        fi
        acquire_recovery_guard "$recovery_guard" "$observed_sha" "$owner_pid" "$owner_transaction" "$owner_child" "$owner_state" "$owner_token" "$owner_pgid" || fail "recovery guard contention prevented stale recovery"
        if [[ "${POINTER_BENCHMARK_CRASH_AFTER_RECOVERY_GUARD:-0}" == 1 ]]; then
            kill -KILL "$$"
        fi
        if ! validate_profile_lock_file "$lock" || \
           [[ "$(lock_fingerprint "$lock")" != "$observed_sha" ]] || \
           [[ "$profile_lock_pid" != "$owner_pid" || "$profile_lock_transaction" != "$owner_transaction" || \
              "$profile_lock_child" != "$owner_child" || "$profile_lock_child_state" != "$owner_state" || \
              "$profile_lock_child_token" != "$owner_token" || "$profile_lock_child_pgid" != "$owner_pgid" ]]; then
            release_recovery_guard
            fail "profile lock changed during stale recovery"
        fi
        if kill -0 "$owner_pid" 2>/dev/null || \
           { [[ "$owner_child" != none ]] && kill -0 "$owner_child" 2>/dev/null; } || \
           { [[ "$owner_pgid" != none ]] && kill -0 "-$owner_pgid" 2>/dev/null; }; then
            release_recovery_guard
            fail "profile lock owner became live during stale recovery"
        fi
        if [[ "$owner_state" == starting ]]; then
            recover_stale_starting_child "$lock" "$owner_transaction" "$owner_token"
        else
            recover_stale_child_namespace "$lock" "$owner_transaction"
        fi
        rm -f -- "$lock"
        durable_sync lock-recovery
        release_recovery_guard
        if [[ -e "$lock.tmp" || -L "$lock.tmp" ]]; then
            [[ -f "$lock.tmp" && ! -L "$lock.tmp" ]] || fail "profile lock temporary path is not a regular file: $lock.tmp"
            rm -f -- "$lock.tmp"
        fi
    done
    fail "could not acquire profile lock after $attempt attempts: $lock"
}

update_profile_lock_child() {
    local state="$1"
    local token="$2"
    local child="$3"
    local pgid="$4"
    validate_profile_lock_child_tuple "$state" "$token" "$child" "$pgid" || return 1
    [[ "${profile_lock_acquired:-false}" == true ]] || return 1
    [[ -f "$profile_lock" && ! -L "$profile_lock" ]] || return 1
    local temporary="$profile_lock.tmp"
    [[ ! -L "$temporary" ]] || return 1
    printf '%s\n' \
        'version=1' \
        "pid=$$" \
        "transaction=$transaction_id" \
        "child=$child" \
        "child-state=$state" \
        "child-token=$token" \
        "child-pgid=$pgid" > "$temporary" || return 1
    validate_profile_lock_file "$temporary" "$$" "$transaction_id" || return 1
    mv -f -- "$temporary" "$profile_lock" || return 1
    durable_sync lock-update
}

validate_profile_lock_child_tuple() {
    local state="$1"
    local token="$2"
    local child="$3"
    local pgid="$4"
    case "$state" in
        idle)
            [[ "$token" == none && "$child" == none && "$pgid" == none ]] || return 1
            ;;
        starting)
            [[ "$token" != none && "$token" =~ ^[A-Za-z0-9._-]+$ && "$child" == none && "$pgid" == none ]] || return 1
            ;;
        running)
            [[ "$token" != none && "$token" =~ ^[A-Za-z0-9._-]+$ && "$child" =~ ^[1-9][0-9]*$ && "$pgid" =~ ^[1-9][0-9]*$ && "$child" == "$pgid" ]] || return 1
            ;;
        *)
            return 1
            ;;
    esac
}

validate_profile_lock_file() {
    local lock="$1"
    local expected_pid="${2:-}"
    local expected_transaction="${3:-}"
    [[ -f "$lock" && ! -L "$lock" ]] || return 1
    [[ "$(sed -n '1p' "$lock")" == version=1 ]] || return 1

    local pid_line
    pid_line="$(sed -n '2p' "$lock")"
    [[ "$pid_line" == pid=* ]] || return 1
    profile_lock_pid="${pid_line#pid=}"
    [[ "$profile_lock_pid" =~ ^[1-9][0-9]*$ ]] || return 1

    local transaction_line
    transaction_line="$(sed -n '3p' "$lock")"
    [[ "$transaction_line" == transaction=* ]] || return 1
    profile_lock_transaction="${transaction_line#transaction=}"
    [[ "$profile_lock_transaction" =~ ^[A-Za-z0-9._-]+$ ]] || return 1

    local child_line
    child_line="$(sed -n '4p' "$lock")"
    [[ "$child_line" == child=* ]] || return 1
    profile_lock_child="${child_line#child=}"

    local state_line
    state_line="$(sed -n '5p' "$lock")"
    [[ "$state_line" == child-state=* ]] || return 1
    profile_lock_child_state="${state_line#child-state=}"

    local token_line
    token_line="$(sed -n '6p' "$lock")"
    [[ "$token_line" == child-token=* ]] || return 1
    profile_lock_child_token="${token_line#child-token=}"

    local pgid_line
    pgid_line="$(sed -n '7p' "$lock")"
    [[ "$pgid_line" == child-pgid=* ]] || return 1
    profile_lock_child_pgid="${pgid_line#child-pgid=}"

    [[ -z "$(sed -n '8p' "$lock")" ]] || return 1
    [[ -z "$expected_pid" || "$profile_lock_pid" == "$expected_pid" ]] || return 1
    [[ -z "$expected_transaction" || "$profile_lock_transaction" == "$expected_transaction" ]] || return 1
}

lock_fingerprint() {
    /usr/bin/shasum -a 256 "$1" | awk '{print $1}'
}

validate_recovery_guard_file() {
    local guard="$1"
    [[ -f "$guard" && ! -L "$guard" ]] || return 1
    [[ "$(sed -n '1p' "$guard")" == version=1 ]] || return 1
    local owner_line
    owner_line="$(sed -n '2p' "$guard")"
    [[ "$owner_line" == pid=* ]] || return 1
    recovery_guard_pid="${owner_line#pid=}"
    [[ "$recovery_guard_pid" =~ ^[1-9][0-9]*$ ]] || return 1
    local transaction_line
    transaction_line="$(sed -n '3p' "$guard")"
    [[ "$transaction_line" == transaction=* ]] || return 1
    recovery_guard_transaction="${transaction_line#transaction=}"
    [[ "$recovery_guard_transaction" =~ ^[A-Za-z0-9._-]+$ ]] || return 1
    local fingerprint_line
    fingerprint_line="$(sed -n '4p' "$guard")"
    [[ "$fingerprint_line" == observed-sha=* ]] || return 1
    recovery_guard_observed_sha="${fingerprint_line#observed-sha=}"
    [[ "$recovery_guard_observed_sha" =~ ^[0-9a-f]{64}$ ]] || return 1
    local observed_pid_line
    observed_pid_line="$(sed -n '5p' "$guard")"
    [[ "$observed_pid_line" == observed-pid=* ]] || return 1
    recovery_guard_observed_pid="${observed_pid_line#observed-pid=}"
    local observed_transaction_line
    observed_transaction_line="$(sed -n '6p' "$guard")"
    [[ "$observed_transaction_line" == observed-transaction=* ]] || return 1
    recovery_guard_observed_transaction="${observed_transaction_line#observed-transaction=}"
    [[ "$recovery_guard_observed_transaction" =~ ^[A-Za-z0-9._-]+$ ]] || return 1
    local observed_child_line
    observed_child_line="$(sed -n '7p' "$guard")"
    [[ "$observed_child_line" == observed-child=* ]] || return 1
    recovery_guard_observed_child="${observed_child_line#observed-child=}"
    local observed_state_line
    observed_state_line="$(sed -n '8p' "$guard")"
    [[ "$observed_state_line" == observed-state=* ]] || return 1
    recovery_guard_observed_state="${observed_state_line#observed-state=}"
    local observed_token_line
    observed_token_line="$(sed -n '9p' "$guard")"
    [[ "$observed_token_line" == observed-token=* ]] || return 1
    recovery_guard_observed_token="${observed_token_line#observed-token=}"
    local observed_pgid_line
    observed_pgid_line="$(sed -n '10p' "$guard")"
    [[ "$observed_pgid_line" == observed-pgid=* ]] || return 1
    recovery_guard_observed_pgid="${observed_pgid_line#observed-pgid=}"
    [[ -z "$(sed -n '11p' "$guard")" ]] || return 1
    [[ "$recovery_guard_observed_pid" =~ ^[1-9][0-9]*$ ]] || return 1
    validate_profile_lock_child_tuple "$recovery_guard_observed_state" "$recovery_guard_observed_token" "$recovery_guard_observed_child" "$recovery_guard_observed_pgid"
}

cleanup_recovery_guard_quarantines() {
    local guard="$1"
    local candidate
    for candidate in "$guard".reclaimed.*; do
        [[ -e "$candidate" || -L "$candidate" ]] || continue
        validate_recovery_guard_file "$candidate" || fail "recovery guard quarantine is incomplete: $candidate"
        if kill -0 "$recovery_guard_pid" 2>/dev/null; then
            fail "recovery guard quarantine is held by a live process (pid $recovery_guard_pid)"
        fi
        rm -f -- "$candidate"
        durable_sync recovery-guard-quarantine-cleanup
    done
}

acquire_recovery_guard() {
    local guard="$1"
    local observed_sha="$2"
    local observed_pid="$3"
    local observed_transaction="$4"
    local observed_child="$5"
    local observed_state="$6"
    local observed_token="$7"
    local observed_pgid="$8"
    cleanup_recovery_guard_quarantines "$guard"
    local attempt
    for attempt in 1 2; do
        if ( set -o noclobber; printf '%s\n' \
            'version=1' \
            "pid=$$" \
            "transaction=$transaction_id" \
            "observed-sha=$observed_sha" \
            "observed-pid=$observed_pid" \
            "observed-transaction=$observed_transaction" \
            "observed-child=$observed_child" \
            "observed-state=$observed_state" \
            "observed-token=$observed_token" \
            "observed-pgid=$observed_pgid" > "$guard" ) 2>/dev/null; then
            validate_recovery_guard_file "$guard" || {
                rm -f -- "$guard"
                fail "recovery guard could not be validated after creation"
            }
            recovery_guard="$guard"
            recovery_guard_acquired=true
            durable_sync recovery-guard-create
            if [[ -n "${POINTER_BENCHMARK_RECOVERY_GUARD_READY:-}" ]]; then
                printf 'READY\n' > "$POINTER_BENCHMARK_RECOVERY_GUARD_READY"
                IFS= read -r release < "${POINTER_BENCHMARK_RECOVERY_GUARD_RELEASE:?}"
                [[ "$release" == RELEASE ]] || fail "recovery guard barrier release is invalid"
            fi
            return 0
        fi
        [[ -f "$guard" && ! -L "$guard" ]] || fail "recovery guard is not a regular file: $guard"
        validate_recovery_guard_file "$guard" || fail "recovery guard has invalid contents"
        if kill -0 "$recovery_guard_pid" 2>/dev/null; then
            fail "recovery guard is held by a live process (pid $recovery_guard_pid)"
        fi
        local quarantine="$guard.reclaimed.$recovery_guard_transaction.$recovery_guard_pid.$transaction_id"
        [[ ! -e "$quarantine" && ! -L "$quarantine" ]] || fail "recovery guard quarantine already exists: $quarantine"
        if ! mv -- "$guard" "$quarantine"; then
            return 1
        fi
        durable_sync recovery-guard-quarantine
        if [[ -n "${POINTER_BENCHMARK_RECOVERY_GUARD_RECLAIM_READY:-}" ]]; then
            printf 'READY\n' > "$POINTER_BENCHMARK_RECOVERY_GUARD_RECLAIM_READY"
            IFS= read -r release < "${POINTER_BENCHMARK_RECOVERY_GUARD_RECLAIM_RELEASE:?}"
            [[ "$release" == RELEASE ]] || fail "recovery guard reclaim barrier release is invalid"
        fi
        validate_recovery_guard_file "$quarantine" || fail "recovery guard quarantine is incomplete: $quarantine"
        rm -f -- "$quarantine"
        durable_sync recovery-guard-quarantine-cleanup
    done
    return 1
}

release_recovery_guard() {
    if [[ "${recovery_guard_acquired:-false}" != true ]]; then
        return
    fi
    if [[ -f "$recovery_guard" && ! -L "$recovery_guard" ]] && \
       validate_recovery_guard_file "$recovery_guard" && \
       [[ "$recovery_guard_pid" == "$$" && "$recovery_guard_transaction" == "$transaction_id" ]]; then
        if rm -f -- "$recovery_guard"; then
            durable_sync recovery-guard-release
        fi
    fi
    recovery_guard_acquired=false
}

release_profile_lock() {
    if [[ "${profile_lock_acquired:-false}" != true ]]; then
        return
    fi
    if [[ -f "$profile_lock" && ! -L "$profile_lock" ]]; then
        if validate_profile_lock_file "$profile_lock" "$$" "$transaction_id" && \
           validate_profile_lock_child_tuple "$profile_lock_child_state" "$profile_lock_child_token" "$profile_lock_child" "$profile_lock_child_pgid" && \
           [[ "$profile_lock_child_state" == idle && "$profile_lock_child_pgid" == none ]]; then
            if rm -f -- "$profile_lock"; then
                durable_sync lock-release
            fi
        fi
    fi
    if [[ -f "$profile_lock.tmp" && ! -L "$profile_lock.tmp" ]]; then
        rm -f -- "$profile_lock.tmp" || true
    fi
    profile_lock_acquired=false
}

process_group_is_live() {
    local pgid="$1"
    [[ "$pgid" != none && "$pgid" =~ ^[0-9]+$ ]] || return 1
    kill -0 "-$pgid" 2>/dev/null
}

wait_for_process_group_exit() {
    local pgid="$1"
    local attempts=0
    while process_group_is_live "$pgid"; do
        ((attempts += 1))
        if (( attempts >= 200 )); then
            kill -KILL "-$pgid" 2>/dev/null || true
            if process_group_is_live "$pgid"; then
                return 1
            fi
            return 0
        fi
        /bin/sleep 0.01
    done
    return 0
}

stop_active_child() {
    local signal="$1"
    local child="$active_child_pid"
    local pgid="$active_child_pgid"
    [[ -n "$child" ]] || return 0
    if [[ "$child_gate_fd_open" == true ]]; then
        exec 7>&- || true
        child_gate_fd_open=false
    fi
    if [[ "$child_ready_fd_open" == true ]]; then
        exec 8>&- || true
        child_ready_fd_open=false
    fi
    if [[ "$pgid" != none && -n "$pgid" ]]; then
        kill -"$signal" "-$pgid" 2>/dev/null || true
    else
        kill -"$signal" "$child" 2>/dev/null || true
    fi
    wait "$child" 2>/dev/null || true
    if [[ "$pgid" != none && -n "$pgid" ]]; then
        if ! wait_for_process_group_exit "$pgid"; then
            kill -KILL "-$pgid" 2>/dev/null || true
            wait_for_process_group_exit "$pgid" || return 1
        fi
    fi
    update_profile_lock_child idle none none none || return 1
    active_child_pid=""
    active_child_pgid="none"
    return 0
}

require_value() {
    local option="$1"
    (( $# >= 2 )) || fail "$option requires a value"
    [[ "$2" != --* ]] || fail "$option requires a value"
}

fixture_profile=""
baseline_commit_sha=""
candidate_commit_sha=""
baseline_root=""
candidate_root=""
baseline_executable=""
candidate_executable=""
baseline_provenance=""
candidate_provenance=""
pair_eligibility_file=""
output_dir=""
runner=""
publish_hook=""
post_rename_publish_hook=""
profile_lock=""
profile_lock_acquired=false
recovery_guard=""
recovery_guard_acquired=false
transaction_id=""
active_child_pid=""
active_child_pgid="none"
script_pgid=""
child_gate_fd_open=false
child_ready_fd_open=false
child_control_dir=""
child_control_owned=false
child_sequence=0

while (( $# > 0 )); do
    case "$1" in
        --authoritative|--compare|--publish|--quality-compare)
            fail "$1 is unavailable before the F foundation; diagnostic finalization is the only supported mode"
            ;;
        --foundation-provenance|--manual-evidence-dir)
            fail "$1 is not part of the pre-F diagnostic protocol"
            ;;
        --fixture-profile)
            require_value "$@"
            [[ -z "$fixture_profile" ]] || fail "--fixture-profile may be supplied only once"
            fixture_profile="$2"
            shift 2
            ;;
        --baseline-commit-sha)
            require_value "$@"
            [[ -z "$baseline_commit_sha" ]] || fail "--baseline-commit-sha may be supplied only once"
            baseline_commit_sha="$2"
            shift 2
            ;;
        --candidate-commit-sha)
            require_value "$@"
            [[ -z "$candidate_commit_sha" ]] || fail "--candidate-commit-sha may be supplied only once"
            candidate_commit_sha="$2"
            shift 2
            ;;
        --baseline-root)
            require_value "$@"
            [[ -z "$baseline_root" ]] || fail "--baseline-root may be supplied only once"
            baseline_root="$2"
            shift 2
            ;;
        --candidate-root)
            require_value "$@"
            [[ -z "$candidate_root" ]] || fail "--candidate-root may be supplied only once"
            candidate_root="$2"
            shift 2
            ;;
        --baseline-executable)
            require_value "$@"
            [[ -z "$baseline_executable" ]] || fail "--baseline-executable may be supplied only once"
            baseline_executable="$2"
            shift 2
            ;;
        --candidate-executable)
            require_value "$@"
            [[ -z "$candidate_executable" ]] || fail "--candidate-executable may be supplied only once"
            candidate_executable="$2"
            shift 2
            ;;
        --baseline-run-provenance)
            require_value "$@"
            [[ -z "$baseline_provenance" ]] || fail "baseline provenance may be supplied only once"
            baseline_provenance="$2"
            shift 2
            ;;
        --candidate-run-provenance)
            require_value "$@"
            [[ -z "$candidate_provenance" ]] || fail "candidate provenance may be supplied only once"
            candidate_provenance="$2"
            shift 2
            ;;
        --pair-eligibility-file)
            require_value "$@"
            [[ -z "$pair_eligibility_file" ]] || fail "--pair-eligibility-file may be supplied only once"
            pair_eligibility_file="$2"
            shift 2
            ;;
        --output-dir)
            require_value "$@"
            [[ -z "$output_dir" ]] || fail "--output-dir may be supplied only once"
            output_dir="$2"
            shift 2
            ;;
        --runner)
            require_value "$@"
            [[ -z "$runner" ]] || fail "--runner may be supplied only once"
            runner="$2"
            shift 2
            ;;
        --publish-hook)
            require_value "$@"
            [[ -z "$publish_hook" ]] || fail "--publish-hook may be supplied only once"
            publish_hook="$2"
            shift 2
            ;;
        --post-rename-publish-hook)
            require_value "$@"
            [[ -z "$post_rename_publish_hook" ]] || fail "--post-rename-publish-hook may be supplied only once"
            post_rename_publish_hook="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            fail "unknown option: $1"
            ;;
    esac
done

[[ -n "$fixture_profile" ]] || fail "--fixture-profile is required"
case "$fixture_profile" in
    standard12|dense1000) ;;
    *) fail "unsupported fixture profile: $fixture_profile" ;;
esac

[[ -n "$baseline_commit_sha" ]] || fail "--baseline-commit-sha is required"
[[ -n "$candidate_commit_sha" ]] || fail "--candidate-commit-sha is required"
[[ "$baseline_commit_sha" =~ ^[0-9a-f]{40}$ ]] || fail "baseline commit must be 40 lowercase hexadecimal characters"
[[ "$candidate_commit_sha" =~ ^[0-9a-f]{40}$ ]] || fail "candidate commit must be 40 lowercase hexadecimal characters"
[[ "$baseline_commit_sha" != "$candidate_commit_sha" ]] || fail "baseline and candidate commits must differ"
[[ -n "$baseline_root" ]] || fail "--baseline-root is required"
[[ -n "$candidate_root" ]] || fail "--candidate-root is required"
[[ -n "$baseline_provenance" ]] || fail "--baseline-run-provenance is required"
[[ -n "$candidate_provenance" ]] || fail "--candidate-run-provenance is required"
[[ -n "$pair_eligibility_file" ]] || fail "--pair-eligibility-file is required"
[[ -n "$output_dir" ]] || fail "--output-dir is required"

baseline_root="$(canonical_directory "$baseline_root" "baseline root")"
candidate_root="$(canonical_directory "$candidate_root" "candidate root")"
[[ "$baseline_root" != "$candidate_root" ]] || fail "baseline and candidate roots must differ"
repo_root="${baseline_root%/build/"$fixture_profile"/baseline}"
[[ "$repo_root" != "$baseline_root" && -n "$repo_root" ]] || fail "baseline root is not scoped to the repository build tree"
expected_baseline_root="$repo_root/build/$fixture_profile/baseline"
expected_candidate_root="$repo_root/build/$fixture_profile/candidate"
[[ "$baseline_root" == "$expected_baseline_root" ]] || fail "baseline root must be exactly $expected_baseline_root"
[[ "$candidate_root" == "$expected_candidate_root" ]] || fail "candidate root must be exactly $expected_candidate_root"
[[ "$repo_root" == "$root_dir" ]] || fail "repository root must match the repository containing the benchmark script: $root_dir"
profile_root="$repo_root/build/$fixture_profile"
if path_contains "$baseline_root" "$candidate_root" || path_contains "$candidate_root" "$baseline_root"; then
    fail "baseline and candidate trees must be disjoint"
fi
output_candidate="$(resolve_path "$output_dir")"
reject_traversal "$output_candidate"
[[ "$output_candidate" != "/" ]] || fail "profile evidence cannot be the filesystem root"
expected_output_dir="$repo_root/.codex/sdd/reports/quality-campaign/performance/$fixture_profile"
[[ "$output_candidate" == "$expected_output_dir" ]] || fail "output directory must be exactly $expected_output_dir"
if path_contains "$baseline_root" "$output_candidate" || path_contains "$output_candidate" "$baseline_root" || \
   path_contains "$candidate_root" "$output_candidate" || path_contains "$output_candidate" "$candidate_root"; then
    fail "profile evidence must be outside build roots"
fi

output_dir="$(canonical_destination "$output_dir" "profile evidence")"
output_parent="$(dirname -- "$output_dir")"
lock_parent="$(physical_ancestor "$output_parent" "profile lock parent")"
profile_lock="$lock_parent/.benchmark-quality.lock.$fixture_profile"
recovery_guard="$lock_parent/.benchmark-quality.recovery.$fixture_profile"
transaction_id="$fixture_profile-$$-$(date +%s)"
acquire_profile_lock "$profile_lock"
trap release_profile_lock EXIT
mkdir -p -- "$output_parent"
output_dir="$(canonical_destination "$output_dir" "profile evidence")"
staging_parent="$output_parent/.benchmark-quality.pending.$fixture_profile"
backup_parent="$output_parent/.benchmark-quality.backup.$fixture_profile"
backup_output="$backup_parent/$fixture_profile"
transaction_journal="$output_parent/.benchmark-quality.transaction.$fixture_profile"
child_control_dir="$output_parent/.benchmark-quality.children.$fixture_profile.$transaction_id"
transaction_had_existing=false
recover_pending_transaction

pair_eligibility_file="$(canonical_file "$pair_eligibility_file" "pair eligibility")"
expected_pair_eligibility="$output_dir/comparisons/pair-eligibility.json"
[[ "$pair_eligibility_file" == "$expected_pair_eligibility" ]] || fail "pair eligibility must be profile-scoped at $expected_pair_eligibility"

[[ "$output_dir" == "$expected_output_dir" ]] || fail "output directory must be exactly $expected_output_dir"
if path_contains "$baseline_root" "$output_dir" || path_contains "$output_dir" "$baseline_root" || \
   path_contains "$candidate_root" "$output_dir" || path_contains "$output_dir" "$candidate_root"; then
    fail "profile evidence must be outside build roots"
fi

if [[ -z "$baseline_executable" ]]; then
    baseline_executable="$baseline_root/Pointer.app/Contents/MacOS/Pointer"
fi
baseline_executable="$(canonical_file "$baseline_executable" "baseline executable")"
if [[ -z "$candidate_executable" ]]; then
    candidate_executable="$candidate_root/Pointer.app/Contents/MacOS/Pointer"
fi
candidate_executable="$(canonical_file "$candidate_executable" "candidate executable")"
baseline_provenance="$(canonical_file "$baseline_provenance" "baseline run provenance")"
candidate_provenance="$(canonical_file "$candidate_provenance" "candidate run provenance")"
if [[ -n "$runner" ]]; then
    runner="$(canonical_file "$runner" "runner")"
fi
if [[ -n "$publish_hook" ]]; then
    publish_hook="$(canonical_file "$publish_hook" "publish hook")"
fi
if [[ -n "$post_rename_publish_hook" ]]; then
    post_rename_publish_hook="$(canonical_file "$post_rename_publish_hook" "post-rename publish hook")"
fi

[[ -x "$baseline_executable" ]] || fail "baseline executable is missing or not executable: $baseline_executable"
[[ -x "$candidate_executable" ]] || fail "candidate executable is missing or not executable: $candidate_executable"
[[ "$baseline_executable" == "$baseline_root/"* ]] || fail "baseline executable must belong to the baseline root"
[[ "$candidate_executable" == "$candidate_root/"* ]] || fail "candidate executable must belong to the candidate root"
[[ "$baseline_provenance" == "$baseline_root/"* ]] || fail "baseline provenance must belong to the baseline root"
[[ "$candidate_provenance" == "$candidate_root/"* ]] || fail "candidate provenance must belong to the candidate root"
if [[ -n "$runner" ]]; then
    [[ -x "$runner" ]] || fail "runner is missing or not executable: $runner"
fi

publish_state="not-started"
cleanup() {
    local exit_code=$?
    trap - EXIT INT TERM
    if [[ -n "$active_child_pid" ]]; then
        stop_active_child TERM || exit_code=1
    fi
    if [[ "$publish_state" != "committed" && -e "$backup_output" ]]; then
        local restore_allowed=true
        if [[ -e "$output_dir" || -L "$output_dir" ]]; then
            if [[ -d "$output_dir" && ! -L "$output_dir" ]] && rm -rf -- "$output_dir"; then
                :
            else
                echo "benchmark-quality.sh: could not remove newly installed profile evidence after interruption" >&2
                restore_allowed=false
                exit_code=1
            fi
        fi
        if [[ "$restore_allowed" == true && ! -e "$output_dir" ]] && mv -- "$backup_output" "$output_dir"; then
            publish_state="restored"
        elif [[ "$restore_allowed" == true ]]; then
            echo "benchmark-quality.sh: could not restore existing profile evidence after interruption" >&2
            exit_code=1
        fi
    fi
    if [[ "$publish_state" == installed && "$transaction_had_existing" == false && ( -e "$output_dir" || -L "$output_dir" ) ]]; then
        if [[ -d "$output_dir" && ! -L "$output_dir" ]]; then
            rm -rf -- "$output_dir" || true
        else
            echo "benchmark-quality.sh: could not remove newly installed profile evidence after interruption" >&2
            exit_code=1
        fi
    fi
    if [[ -d "$staging_parent" && ! -L "$staging_parent" ]]; then
        rm -rf -- "$staging_parent" || true
    fi
    if [[ -d "$backup_parent" && ! -L "$backup_parent" ]]; then
        rm -rf -- "$backup_parent" || true
    fi
    if [[ -f "$transaction_journal" && ! -L "$transaction_journal" ]]; then
        rm -f -- "$transaction_journal" || true
    fi
    if [[ -f "$transaction_journal.tmp" && ! -L "$transaction_journal.tmp" ]]; then
        rm -f -- "$transaction_journal.tmp" || true
    fi
    if [[ "$child_control_owned" == true && -z "$active_child_pid" && -d "$child_control_dir" && ! -L "$child_control_dir" ]]; then
        rm -rf -- "$child_control_dir" || exit_code=1
    fi
    release_recovery_guard
    release_profile_lock
    exit "$exit_code"
}

handle_signal() {
    local signal="$1"
    local exit_code="$2"
    if [[ -n "$active_child_pid" ]]; then
        stop_active_child "$signal" || true
    fi
    exit "$exit_code"
}

trap cleanup EXIT
trap 'handle_signal INT 130' INT
trap 'handle_signal TERM 143' TERM

validate_json_files "$baseline_provenance" "$candidate_provenance" "$pair_eligibility_file"
script_pgid="$(/bin/ps -o pgid= -p "$$" | tr -d '[:space:]')"
[[ "$script_pgid" =~ ^[1-9][0-9]*$ ]] || fail "could not determine benchmark shell process group"
partial_dir="$(canonical_destination "$profile_root/pair-execution/partial" "pair execution partial")"
mkdir -p -- "$partial_dir"

if [[ -e "$output_dir" || -L "$output_dir" ]]; then
    [[ -d "$output_dir" && ! -L "$output_dir" ]] || fail "profile evidence is not a physical directory: $output_dir"
    transaction_had_existing=true
else
    transaction_had_existing=false
fi
write_transaction_journal prepared
[[ ! -e "$child_control_dir" && ! -L "$child_control_dir" ]] || fail "child control path already exists: $child_control_dir"
mkdir -- "$child_control_dir"
child_control_owned=true

invoke_tracked_child() {
    local context="$1"
    local kind="$2"
    shift 2
    child_sequence=$((child_sequence + 1))
    local child_token="$transaction_id-$child_sequence"
    local gate="$child_control_dir/$child_token.gate"
    local ready="$child_control_dir/$child_token.ready"
    local owner="$child_control_dir/$child_token.owner"
    local capability="$child_control_dir/$child_token.capability"
    /usr/bin/mkfifo "$gate" "$ready" || return 125
    exec 7<> "$gate"
    child_gate_fd_open=true
    exec 8<> "$ready"
    child_ready_fd_open=true
    printf '%s\n' 'version=1' "transaction=$transaction_id" "token=$child_token" > "$capability" || return 125
    durable_sync child-capability
    if ! update_profile_lock_child starting "$child_token" none none; then
        exec 7>&- || true
        exec 8>&- || true
        child_gate_fd_open=false
        child_ready_fd_open=false
        return 125
    fi
    if [[ "${POINTER_BENCHMARK_CRASH_AFTER_STARTING:-0}" == 1 ]]; then
        kill -KILL "$$"
    fi

    # shellcheck disable=SC2016
    local wrapper_code='
set -euo pipefail
gate="$1"
ready="$2"
owner="$3"
token="$4"
kind="$5"
parent_pgid="$6"
lock="$7"
transaction="$8"
capability="$9"
shift 9
exec 7>&-
pgid="$(/bin/ps -o pgid= -p "$$" | tr -d "[:space:]")"
[[ "$pgid" =~ ^[1-9][0-9]*$ ]]
[[ "$pgid" != "$parent_pgid" ]]
[[ "$pgid" == "$$" ]]
verify_capability() {
    [[ -f "$capability" && ! -L "$capability" ]]
    [[ ! -e "$capability.revoked" && ! -L "$capability.revoked" ]]
    [[ "$(sed -n "1p" "$capability")" == "version=1" ]]
    [[ "$(sed -n "2p" "$capability")" == "transaction=$transaction" ]]
    [[ "$(sed -n "3p" "$capability")" == "token=$token" ]]
    [[ -z "$(sed -n "4p" "$capability")" ]]
    [[ "$(sed -n "3p" "$lock")" == "transaction=$transaction" ]]
    [[ "$(sed -n "6p" "$lock")" == "child-token=$token" ]]
}
verify_starting_capability() {
    verify_capability
    [[ "$(sed -n "5p" "$lock")" == "child-state=starting" ]]
}
verify_running_capability() {
    verify_capability
    [[ "$(sed -n "5p" "$lock")" == "child-state=running" ]]
    [[ "$(sed -n "4p" "$lock")" == "child=$$" ]]
    [[ "$(sed -n "7p" "$lock")" == "child-pgid=$pgid" ]]
}
if [[ "${POINTER_BENCHMARK_CRASH_BEFORE_OWNER:-0}" == 1 ]]; then
    kill -KILL "$PPID"
    /bin/sleep "${POINTER_BENCHMARK_CRASH_BEFORE_OWNER_DELAY:-0.05}"
    if [[ -n "${POINTER_BENCHMARK_CRASH_BEFORE_OWNER_DONE:-}" ]]; then
        printf "DONE\\n" > "${POINTER_BENCHMARK_CRASH_BEFORE_OWNER_DONE}"
    fi
fi
verify_starting_capability
owner_temporary="$owner.tmp"
printf "%s\n" "token=$token" "pid=$$" "pgid=$pgid" > "$owner_temporary"
mv -f -- "$owner_temporary" "$owner"
printf "ready\n" > "$ready"
exec 8>&-
exec 3< "$gate"
IFS= read -r release <&3 || exit 143
[[ "$release" == go ]] || exit 143
exec 3<&-
verify_running_capability
if [[ "$kind" == hook ]]; then
    POINTER_BENCHMARK_STAGING="$POINTER_BENCHMARK_STAGING" POINTER_BENCHMARK_OUTPUT="$POINTER_BENCHMARK_OUTPUT" exec "$@"
else
    exec "$@"
fi
'
    if [[ "$kind" == hook ]]; then
        POINTER_BENCHMARK_STAGING="$staging_output_dir" POINTER_BENCHMARK_OUTPUT="$output_dir" \
            /bin/bash -c "$wrapper_code" _ "$gate" "$ready" "$owner" "$child_token" "$kind" "$script_pgid" "$profile_lock" "$transaction_id" "$capability" "$@" &
    else
        /bin/bash -c "$wrapper_code" _ "$gate" "$ready" "$owner" "$child_token" "$kind" "$script_pgid" "$profile_lock" "$transaction_id" "$capability" "$@" &
    fi
    local child_pid=$!
    active_child_pid="$child_pid"
    IFS= read -r -t 5 ready_value <&8 || return 125
    exec 8<&-
    child_ready_fd_open=false
    [[ "$ready_value" == ready ]] || return 125
    [[ -f "$owner" && ! -L "$owner" ]] || return 125
    [[ -z "$(sed -n '4p' "$owner")" ]] || return 125
    local owner_token
    owner_token="$(sed -n '1p' "$owner")"
    owner_token="${owner_token#token=}"
    local owner_pid
    owner_pid="$(sed -n '2p' "$owner")"
    owner_pid="${owner_pid#pid=}"
    local owner_pgid
    owner_pgid="$(sed -n '3p' "$owner")"
    owner_pgid="${owner_pgid#pgid=}"
    [[ "$owner_token" == "$child_token" && "$owner_pid" == "$child_pid" ]] || return 125
    [[ "$owner_pgid" =~ ^[1-9][0-9]*$ && "$owner_pgid" == "$owner_pid" && "$owner_pgid" != "$script_pgid" ]] || return 125
    active_child_pgid="$owner_pgid"
    if [[ "${POINTER_BENCHMARK_CRASH_AFTER_READY:-0}" == 1 ]]; then
        kill -KILL "$$"
    fi
    if ! update_profile_lock_child running "$child_token" "$owner_pid" "$owner_pgid"; then
        stop_active_child TERM || true
        return 125
    fi
    printf 'go\n' >&7 || return 125
    exec 7>&-
    child_gate_fd_open=false
    local child_exit=0
    if wait "$child_pid"; then
        child_exit=0
    else
        child_exit=$?
    fi
    if ! wait_for_process_group_exit "$owner_pgid"; then
        kill -KILL "-$owner_pgid" 2>/dev/null || true
        wait_for_process_group_exit "$owner_pgid" || return 124
    fi
    rm -f -- "$gate" "$ready" "$owner" "$owner.tmp" "$capability" "$capability.revoked"
    if [[ "$active_child_pid" == "$child_pid" ]]; then
        update_profile_lock_child idle none none none || return 125
        active_child_pid=""
        active_child_pgid="none"
    fi
    return "$child_exit"
}

invoke_cli() {
    local executable="$1"
    local context="$2"
    shift 2
    local child_exit=0
    if [[ -n "$runner" ]]; then
        if invoke_tracked_child "$context" cli "$runner" "$executable" "$@"; then
            return 0
        else
            child_exit=$?
        fi
        fail "runner failed during $context (exit $child_exit)"
    fi
    if invoke_tracked_child "$context" cli "$executable" "$@"; then
        return 0
    else
        child_exit=$?
    fi
    fail "executable failed during $context (exit $child_exit)"
}

run_trial() {
    local variant="$1"
    local executable="$2"
    local commit_sha="$3"
    local provenance="$4"
    local pair_order="$5"
    local pair_index="$6"
    invoke_cli "$executable" "trial $variant $pair_order $pair_index" \
        --quality-performance --format json --operation trial \
        --fixture-profile "$fixture_profile" \
        --variant "$variant" \
        --pair-order "$pair_order" \
        --pair-index "$pair_index" \
        --source-commit-sha "$commit_sha" \
        --run-provenance-file "$provenance" \
        --pair-eligibility-file "$pair_eligibility_file" \
        --partial-pair-directory "$partial_dir"
}

for ((pair_index = 0; pair_index < 15; pair_index++)); do
    run_trial baseline "$baseline_executable" "$baseline_commit_sha" "$baseline_provenance" baselineFirst "$pair_index"
    run_trial candidate "$candidate_executable" "$candidate_commit_sha" "$candidate_provenance" baselineFirst "$pair_index"
done
for ((pair_index = 15; pair_index < 30; pair_index++)); do
    run_trial candidate "$candidate_executable" "$candidate_commit_sha" "$candidate_provenance" candidateFirst "$pair_index"
    run_trial baseline "$baseline_executable" "$baseline_commit_sha" "$baseline_provenance" candidateFirst "$pair_index"
done

[[ ! -e "$staging_parent" && ! -L "$staging_parent" ]] || fail "orphaned transaction staging requires recovery: $staging_parent"
mkdir -- "$staging_parent"
staging_output_dir="$staging_parent/$fixture_profile"
mkdir -- "$staging_output_dir"
mkdir -p "$staging_output_dir/comparisons"
mkdir -p "$staging_output_dir/provenance"
cp -- "$pair_eligibility_file" "$staging_output_dir/comparisons/pair-eligibility.json"
cp -- "$baseline_provenance" "$staging_output_dir/provenance/baseline.json"
cp -- "$candidate_provenance" "$staging_output_dir/provenance/candidate.json"
invoke_cli "$candidate_executable" "pair finalization" \
    --quality-performance --format json --operation finalize \
    --fixture-profile "$fixture_profile" \
    --partial-pair-directory "$partial_dir" \
    --baseline-run-provenance-file "$baseline_provenance" \
    --candidate-run-provenance-file "$candidate_provenance" \
    --pair-eligibility-file "$pair_eligibility_file" \
    --output-dir "$staging_output_dir"

validate_staged_output "$staging_output_dir"

if [[ -e "$output_dir" ]]; then
    if [[ -e "$output_dir/measurements" || -L "$output_dir/measurements" || \
          -e "$output_dir/pair-execution" || -L "$output_dir/pair-execution" ]]; then
        validate_staged_output "$output_dir"
    else
        validate_existing_preseed "$output_dir"
    fi
    if [[ -d "$output_dir" ]] && diff -qr "$staging_output_dir" "$output_dir" >/dev/null 2>&1; then
        echo "diagnostic performance evidence already finalized: $output_dir"
        exit 0
    fi
    [[ ! -e "$backup_parent" && ! -L "$backup_parent" ]] || fail "orphaned transaction backup requires recovery: $backup_parent"
    mkdir -- "$backup_parent"
    if ! mv -- "$output_dir" "$backup_output"; then
        rm -rf -- "$backup_parent"
        fail "could not stage existing profile evidence for atomic publish"
    fi
    publish_state="backed-up"
    write_transaction_journal backed-up
    if [[ -n "$publish_hook" ]]; then
        if invoke_tracked_child "publish hook" hook "$publish_hook"; then
            :
        else
            hook_exit=$?
            fail "publish hook interrupted atomic publish (exit $hook_exit)"
        fi
    fi
    validate_staged_output "$staging_output_dir"
    if mv -- "$staging_output_dir" "$output_dir"; then
        publish_state="installed"
        write_transaction_journal installed
        if [[ -n "$post_rename_publish_hook" ]]; then
            if invoke_tracked_child "post-rename publish hook" hook "$post_rename_publish_hook"; then
                :
            else
                hook_exit=$?
                fail "post-rename publish hook interrupted atomic publish (exit $hook_exit)"
            fi
        fi
        validate_staged_output "$output_dir"
        if ! rm -rf -- "$backup_parent"; then
            fail "could not remove transaction backup after publish"
        fi
        publish_state="committed"
        if ! rm -f -- "$transaction_journal"; then
            fail "could not remove transaction journal after publish"
        fi
    else
        fail "could not publish staged profile evidence"
    fi
    echo "diagnostic performance evidence finalized: $output_dir"
    exit 0
fi

if mv -- "$staging_output_dir" "$output_dir"; then
    publish_state="installed"
    write_transaction_journal installed
    publish_state="committed"
    if ! rm -f -- "$transaction_journal"; then
        fail "could not remove transaction journal after publish"
    fi
else
    fail "could not publish staged profile evidence"
fi
echo "diagnostic performance evidence finalized: $output_dir"
