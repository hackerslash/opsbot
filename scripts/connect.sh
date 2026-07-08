#!/usr/bin/env bash
#
# opsbot connection helper.
# Resolves a friendly target name to an SSH (PEM + IP) or AWS SSM connection and
# runs one-shot remote commands non-interactively. Reads inventory.json next to the
# skill root. NEVER prints PEM contents or secrets.
#
# Usage:
#   connect.sh list                                        list known targets
#   connect.sh resolve <target>                            show connection details
#   connect.sh ssh <target>                                print interactive ssh line
#   connect.sh run <target> "<command>"                    single target
#   connect.sh run <target> --timeout <s> "<command>"     single target, custom timeout
#   connect.sh run --env <env> --all "<command>"           fleet fan-out by env
#   connect.sh run --tags <tag> --all "<command>"          fleet fan-out by tag
#   connect.sh run --env <env> --tags <tag> --all "<cmd>"  env + tag filter
#   connect.sh run --host IP --key PEM --user U "<cmd>"    ad-hoc host (not in inventory)
#
# Safety:
#   Mutating-looking commands against a prod target are refused unless --confirm-prod
#   is passed. Fleet sweeps that include prod targets also require --confirm-prod.
#   This is a backstop, not a substitute for asking the user.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INVENTORY="${OPSBOT_INVENTORY:-$ROOT_DIR/inventory.json}"

err() { echo "opsbot: $*" >&2; }
die() { err "$*"; exit 1; }

need_jq() {
  command -v jq >/dev/null 2>&1 || die "jq is required. Install it (brew install jq / apt install jq)."
}

ensure_inventory() {
  [[ -f "$INVENTORY" ]] || die "inventory not found at $INVENTORY — copy inventory.example.json to inventory.json and fill it in."
  jq empty "$INVENTORY" 2>/dev/null || die "inventory.json is not valid JSON. Please fix it before continuing."
}

# Print all targets as a table.
cmd_list() {
  ensure_inventory; need_jq
  printf "%-16s %-8s %-16s %-10s %-20s %s\n" TARGET ENV METHOD OS DEST TAGS
  jq -r '
    .targets | to_entries[] |
    [ .key,
      (.value.env // "-"),
      (.value.method // "ssh"),
      (.value.os // "-"),
      ( if (.value.method // "ssh") == "ssm" then (.value.instance_id // "-")
        else ((.value.user // "ubuntu") + "@" + (.value.host // "-")) end ),
      ((.value.tags // []) | join(","))
    ] | @tsv' "$INVENTORY" \
  | while IFS=$'\t' read -r t e m o d g; do
      printf "%-16s %-8s %-16s %-10s %-20s %s\n" "$t" "$e" "$m" "$o" "$d" "$g"
    done
}

# Echo a JSON object for a target, or empty if absent.
target_json() {
  jq -c --arg t "$1" '.targets[$t] // empty' "$INVENTORY"
}

field() { jq -r --arg t "$1" --arg f "$2" '.targets[$t][$f] // ""' "$INVENTORY"; }

is_prod_target() {
  local env name="$1"
  env="$(field "$name" env)"
  [[ "$env" == "prod" ]] || [[ "$name" == *prod* ]] || [[ "$name" == db ]]
}

# Heuristic: does this command change server state?
looks_mutating() {
  local cmd="$1"
  local pattern='\b(rm|mv|dd|mkfs|reboot|shutdown|halt|passwd|adduser|useradd|userdel|groupadd|visudo|crontab)\b|systemctl (restart|stop|start|disable|enable|reload)|apt(-get)? (install|remove|purge|upgrade|autoremove)|dnf (install|remove|upgrade|autoremove)|yum (install|remove|upgrade)|pip[0-9]? (install|uninstall)|npm (ci|install|uninstall)|docker (run|stop|rm|rmi|pull|push|build|compose)|certbot|ufw |firewall-cmd|iptables|ip6tables|wg (set|addconf|syncconf)|aws s3 (rm|mv|cp|sync)|aws (ec2|rds|lambda|iam) |sed -i|tee /|>>?[[:space:]]*/etc|git (reset|checkout|clean|pull|push)|chmod|chown|kill|pkill|killall|truncate|mkswap|swapon|swapoff|ln -sf?|curl .*(sh|bash)|wget .*(sh|bash)|bash <\(|eval '
  echo "$cmd" | grep -Eqi "$pattern"
}

resolve_ssh_dest() {
  local name="$1" host user
  host="$(field "$name" host)"
  user="$(field "$name" user)"; [[ -n "$user" ]] || user="ubuntu"
  [[ -n "$host" ]] || die "target '$name' has no host in inventory."
  echo "$user@$host"
}

resolve_key_path() {
  local name="$1" key keydir
  key="$(field "$name" key)"
  [[ -n "$key" ]] || die "target '$name' has no key in inventory."
  case "$key" in
    /*) echo "$key" ;;
    *)  keydir="$(jq -r '.pem_dir // ""' "$INVENTORY")"
        [[ -n "$keydir" ]] || die "key '$key' is relative but inventory has no pem_dir."
        echo "$keydir/$key" ;;
  esac
}

# Validate that a PEM key file exists and has safe permissions (600 or 400).
check_key_perms() {
  local keypath="$1"
  [[ -f "$keypath" ]] || die "PEM key not found: $keypath"
  local perms
  perms="$(stat -f "%OLp" "$keypath" 2>/dev/null || stat -c "%a" "$keypath" 2>/dev/null || echo "unknown")"
  case "$perms" in
    600|400) ;;
    unknown) err "warning: could not check permissions on $keypath" ;;
    *)       die "PEM key $keypath has permissions $perms — SSH will refuse it. Fix with: chmod 600 '$keypath'" ;;
  esac
}

SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o BatchMode=yes)

cmd_resolve() {
  ensure_inventory; need_jq
  local name="$1"
  [[ -n "$(target_json "$name")" ]] || die "unknown target '$name'. Run 'connect.sh list'."
  local method; method="$(field "$name" method)"; [[ -n "$method" ]] || method="ssh"
  echo "target: $name"
  echo "env:    $(field "$name" env)"
  echo "os:     $(field "$name" os)"
  echo "tags:   $(jq -r --arg t "$name" '.targets[$t].tags // [] | join(", ")' "$INVENTORY")"
  echo "method: $method"
  if [[ "$method" == "ssm" ]]; then
    echo "instance_id: $(field "$name" instance_id)"
  else
    echo "dest:   $(resolve_ssh_dest "$name")"
    echo "key:    $(resolve_key_path "$name")   (path only — never printed contents)"
  fi
  is_prod_target "$name" && echo "WARNING: this is a PRODUCTION target."
  return 0
}

cmd_ssh() {
  ensure_inventory; need_jq
  local name="$1"
  [[ -n "$(target_json "$name")" ]] || die "unknown target '$name'."
  local method; method="$(field "$name" method)"; [[ -n "$method" ]] || method="ssh"
  if [[ "$method" == "ssm" ]]; then
    echo "aws ssm start-session --target $(field "$name" instance_id) --document-name AWS-StartInteractiveCommand --parameters command=\"bash -l\""
  else
    local keypath; keypath="$(resolve_key_path "$name")"
    check_key_perms "$keypath"
    local bastion; bastion="$(jq -r --arg t "$name" '.targets[$t].bastion // ""' "$INVENTORY")"
    if [[ -n "$bastion" ]]; then
      local bkey buser bhost
      bkey="$(resolve_key_path "$bastion")"
      buser="$(field "$bastion" user)"; [[ -n "$buser" ]] || buser="ubuntu"
      bhost="$(field "$bastion" host)"
      echo "ssh -i '$keypath' -o 'ProxyCommand=ssh -i ${bkey} -W %h:%p ${buser}@${bhost}' $(resolve_ssh_dest "$name")  # proxied via $bastion"
    else
      echo "ssh -i '$keypath' $(resolve_ssh_dest "$name")"
    fi
  fi
}

# Run an SSM command synchronously: dispatch, poll get-command-invocation until
# done, print stdout+stderr, exit with the remote exit code.
ssm_run_sync() {
  local iid="$1" cmd="$2"
  command -v aws >/dev/null 2>&1 || die "aws CLI required for SSM target."

  local escaped_cmd
  escaped_cmd="$(echo "$cmd" | sed 's/"/\\"/g')"

  local cmd_id
  cmd_id="$(aws ssm send-command \
    --instance-ids "$iid" \
    --document-name "AWS-RunShellScript" \
    --parameters "commands=[\"$escaped_cmd\"]" \
    --query "Command.CommandId" \
    --output text)" || die "aws ssm send-command failed."

  err "SSM command dispatched: $cmd_id — polling for output..."

  local status="" stdout="" stderr="" rc=0
  local attempts=0 max_attempts=60
  while true; do
    sleep 1
    attempts=$((attempts + 1))
    local result
    result="$(aws ssm get-command-invocation \
      --command-id "$cmd_id" \
      --instance-id "$iid" \
      --output json 2>/dev/null)" || { err "polling error (attempt $attempts)"; continue; }

    status="$(echo "$result" | jq -r '.Status')"
    case "$status" in
      Success|Failed|Cancelled|TimedOut|DeliveryTimedOut|ExecutionTimedOut)
        stdout="$(echo "$result" | jq -r '.StandardOutputContent // ""')"
        stderr="$(echo "$result" | jq -r '.StandardErrorContent // ""')"
        rc="$(echo "$result" | jq -r '.ResponseCode // 1')"
        break ;;
      InProgress|Pending|Delayed) ;;
      *)
        err "unexpected SSM status: $status"
        break ;;
    esac

    if [[ "$attempts" -ge "$max_attempts" ]]; then
      err "SSM command timed out after ${max_attempts}s. CommandId: $cmd_id"
      err "Check manually: aws ssm get-command-invocation --command-id $cmd_id --instance-id $iid"
      exit 1
    fi
  done

  [[ -n "$stdout" ]] && printf '%s\n' "$stdout"
  [[ -n "$stderr" ]] && printf '%s\n' "$stderr" >&2
  exit "$rc"
}

# Run a command on a single known target without exec (used by fleet_run).
# Calls die() on error, which exits with code 1 — safe to call inside a subshell.
_run_single() {
  local t="$1" cmd="$2" timeout="$3"
  local method; method="$(field "$t" method)"; [[ -n "$method" ]] || method="ssh"
  local single_opts=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout="$timeout" -o BatchMode=yes)
  if [[ "$method" == "ssm" ]]; then
    local iid; iid="$(field "$t" instance_id)"
    [[ -n "$iid" ]] || die "$t: no instance_id in inventory."
    ssm_run_sync "$iid" "$cmd"
  else
    local keypath; keypath="$(resolve_key_path "$t")"
    check_key_perms "$keypath"
    local dest; dest="$(resolve_ssh_dest "$t")"
    local bastion; bastion="$(jq -r --arg t "$t" '.targets[$t].bastion // ""' "$INVENTORY")"
    if [[ -n "$bastion" ]]; then
      local bkey buser bhost
      bkey="$(resolve_key_path "$bastion")"
      buser="$(field "$bastion" user)"; [[ -n "$buser" ]] || buser="ubuntu"
      bhost="$(field "$bastion" host)"
      ssh "${single_opts[@]}" -i "$keypath" \
        -o "ProxyCommand=ssh -i ${bkey} -o StrictHostKeyChecking=accept-new -o ConnectTimeout=${timeout} -o BatchMode=yes -W %h:%p ${buser}@${bhost}" \
        "$dest" "$cmd"
    else
      ssh "${single_opts[@]}" -i "$keypath" "$dest" "$cmd"
    fi
  fi
}

# Fan out a command to all targets matching an env/tag filter.
fleet_run() {
  local env_filter="$1" tags_filter="$2" confirm_prod="$3" timeout="$4" cmd="$5"
  ensure_inventory; need_jq

  # Build jq program based on which filters are active
  local jq_prog
  if [[ -n "$env_filter" ]] && [[ -n "$tags_filter" ]]; then
    jq_prog='.targets | to_entries[]
      | select(.value.env == $env
          and (.value.tags // [] | contains([$tag])))
      | .key'
  elif [[ -n "$env_filter" ]]; then
    jq_prog='.targets | to_entries[] | select(.value.env == $env) | .key'
  elif [[ -n "$tags_filter" ]]; then
    jq_prog='.targets | to_entries[]
      | select(.value.tags // [] | contains([$tag]))
      | .key'
  else
    jq_prog='.targets | keys[]'
  fi

  local target_list
  target_list="$(jq -r \
    --arg env "$env_filter" \
    --arg tag "$tags_filter" \
    "$jq_prog" "$INVENTORY")" \
    || die "failed to read inventory."

  [[ -n "$target_list" ]] || \
    die "no targets matched${env_filter:+ env=$env_filter}${tags_filter:+ tags=$tags_filter}."

  # Check for prod targets in the fleet
  local has_prod=0
  while IFS= read -r t; do
    is_prod_target "$t" && { has_prod=1; break; }
  done <<< "$target_list"

  if [[ "$has_prod" -eq 1 ]] && [[ "$confirm_prod" -ne 1 ]]; then
    die "fleet includes PROD targets. Add --confirm-prod to proceed."
  fi
  if [[ "$has_prod" -eq 1 ]] && looks_mutating "$cmd" && [[ "$confirm_prod" -ne 1 ]]; then
    die "refusing mutating fleet command against PROD targets without --confirm-prod."
  fi

  local -a failed=()
  local total=0
  while IFS= read -r t; do
    total=$((total + 1))
    printf '\n=== %s ===\n' "$t"
    # Run in a subshell so die()/exit inside _run_single or ssm_run_sync
    # only exits the subshell, not the fleet loop.
    ( _run_single "$t" "$cmd" "$timeout" ) || failed+=("$t")
  done <<< "$target_list"

  printf '\n'
  if [[ "${#failed[@]}" -gt 0 ]]; then
    err "fleet: $((total - ${#failed[@]}))/${total} OK — failed: ${failed[*]}"
    return 1
  else
    err "fleet: ${total}/${total} OK"
  fi
}

cmd_run() {
  local confirm_prod=0 host="" key="" user="" target="" cmd=""
  local fleet_all=0 env_filter="" tags_filter="" timeout=10
  local -a positional=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --confirm-prod) confirm_prod=1;       shift ;;
      --host)         host="$2";            shift 2 ;;
      --key)          key="$2";             shift 2 ;;
      --user)         user="$2";            shift 2 ;;
      --all)          fleet_all=1;          shift ;;
      --env)          env_filter="$2";      shift 2 ;;
      --tags)         tags_filter="$2";     shift 2 ;;
      --timeout)      timeout="$2";         shift 2 ;;
      --)             shift; positional+=("$@"); break ;;
      -*)             die "unknown flag $1" ;;
      *)              positional+=("$1");   shift ;;
    esac
  done

  if [[ ${#positional[@]} -eq 0 ]]; then
    die "no target or command given."
  fi

  # Ad-hoc SSH: --host given
  if [[ -n "$host" ]]; then
    [[ -n "$key" ]] || die "--host requires --key."
    [[ -n "$user" ]] || user="ubuntu"
    check_key_perms "$key"
    cmd="${positional[*]}"
    exec ssh "${SSH_OPTS[@]}" -i "$key" "$user@$host" "$cmd"
  fi

  # Fleet mode: --all flag
  if [[ "$fleet_all" -eq 1 ]]; then
    cmd="${positional[*]}"
    fleet_run "$env_filter" "$tags_filter" "$confirm_prod" "$timeout" "$cmd"
    return
  fi

  ensure_inventory; need_jq

  target="${positional[0]}"
  if [[ ${#positional[@]} -lt 2 ]]; then
    die "no command given. Usage: connect.sh run <target> \"<remote command>\""
  fi

  if [[ ${#positional[@]} -gt 2 ]]; then
    err "warning: remote command appears to be split across ${#positional[@]} args (did you forget to quote it?)."
    err "  Joining them: ${positional[*]:1}"
  fi
  cmd="${positional[*]:1}"

  [[ -n "$(target_json "$target")" ]] || die "unknown target '$target'. Run 'connect.sh list'."

  if is_prod_target "$target" && looks_mutating "$cmd" && [[ "$confirm_prod" -ne 1 ]]; then
    die "refusing mutating command on PROD target '$target' without --confirm-prod. Command was: $cmd"
  fi

  local method; method="$(field "$target" method)"; [[ -n "$method" ]] || method="ssh"
  local run_opts=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout="$timeout" -o BatchMode=yes)
  if [[ "$method" == "ssm" ]]; then
    local iid; iid="$(field "$target" instance_id)"
    [[ -n "$iid" ]] || die "ssm target '$target' has no instance_id."
    ssm_run_sync "$iid" "$cmd"
  else
    local keypath; keypath="$(resolve_key_path "$target")"
    check_key_perms "$keypath"
    local dest; dest="$(resolve_ssh_dest "$target")"
    local bastion; bastion="$(jq -r --arg t "$target" '.targets[$t].bastion // ""' "$INVENTORY")"
    if [[ -n "$bastion" ]]; then
      local bkey buser bhost
      bkey="$(resolve_key_path "$bastion")"
      buser="$(field "$bastion" user)"; [[ -n "$buser" ]] || buser="ubuntu"
      bhost="$(field "$bastion" host)"
      exec ssh "${run_opts[@]}" -i "$keypath" \
        -o "ProxyCommand=ssh -i ${bkey} -o StrictHostKeyChecking=accept-new -o ConnectTimeout=${timeout} -o BatchMode=yes -W %h:%p ${buser}@${bhost}" \
        "$dest" "$cmd"
    else
      exec ssh "${run_opts[@]}" -i "$keypath" "$dest" "$cmd"
    fi
  fi
}

main() {
  if [[ $# -lt 1 ]]; then
    err "usage: connect.sh {list|resolve|run|ssh} ..."
    err "  list                                      list known targets"
    err "  resolve <target>                          show connection details (no secrets)"
    err "  ssh <target>                              print interactive ssh line to paste"
    err "  run <target> [--timeout N] \"<cmd>\"        run on one target"
    err "  run --env <env> --all [--timeout N] \"<cmd>\"       fleet fan-out by env"
    err "  run --tags <tag> --all [--timeout N] \"<cmd>\"      fleet fan-out by tag"
    err "  run --env E --tags T --all [--timeout N] \"<cmd>\"  fleet with both filters"
    err "  run --host IP --key PEM --user U \"<cmd>\"  ad-hoc host"
    exit 1
  fi
  local sub="$1"; shift
  case "$sub" in
    list)    cmd_list ;;
    resolve) [[ $# -ge 1 ]] || die "resolve needs a target."; cmd_resolve "$1" ;;
    ssh)     [[ $# -ge 1 ]] || die "ssh needs a target.";     cmd_ssh "$1" ;;
    run)     cmd_run "$@" ;;
    *) die "unknown subcommand '$sub'. Use list|resolve|run|ssh." ;;
  esac
}

main "$@"
