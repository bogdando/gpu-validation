#!/usr/bin/env bash
#
# Offline tests for the last-resort vmlinuz resolver in gpu-validation/tasks/kernel_pin.yaml.
# Keep resolver logic here in sync with that task's shell body.
#
# From repo checkout root:
#   bash gpu-validation/scripts/test_kernel_pin_vmlinuz_resolve.sh
set -euo pipefail

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'OK: %s\n' "$1"
}

# KP_BOOT_MOUNT: where vmlinuz files live (default /boot). rpm -ql lines are rewritten
# from /boot/... into ${KP_BOOT_MOUNT}/... before printing.
#
# Args: GV_BOOT_TAG GV_VMLINUZ_PREFIX [spec ...]
last_resort_resolve_vmlinuz() {
  local GV_BOOT_TAG="${1:?}"
  local GV_VMLINUZ_PREFIX="${2:?}"
  shift 2 || true
  local -a specs=("$@")

  local BOOT_MOUNT="${KP_BOOT_MOUNT:-/boot}"
  local spec rpm_out n path rpm_fb last bn p

  map_boot_path() {
    local fp="${1:?}"
    if [[ "${fp}" == /boot/* ]]; then
      printf '%s\n' "${BOOT_MOUNT}/${fp#/boot/}"
      return 0
    fi
    printf '%s\n' "${fp}"
  }

  for spec in "${specs[@]}"; do
    case "$spec" in
      kernel-devel* | kernel-headers*) continue ;;
      kernel-modules-[0-9]* | kernel-modules-core-[0-9]*) continue ;;
      kernel-[0-9]* | kernel-core-[0-9]*) ;;
      *) continue ;;
    esac

    rpm_out=""
    if rpm_out=$(rpm -q "$spec" 2>/dev/null); then
      :
    else
      rpm_out=$(rpm -qa "${spec}*" 2>/dev/null | grep -E '^(kernel|kernel-core)-' || true)
    fi
    [[ -z "${rpm_out}" ]] && continue

    while IFS= read -r n; do
      [[ -z "${n}" ]] && continue
      path="$(rpm -ql "$n" 2>/dev/null \
        | grep -E '^/boot/vmlinuz-' \
        | grep -Ev '\.(hmac|debug|gz)(\.|$)' \
        | head -n1 || true)"
      if [[ -n "${path:-}" ]]; then
        map_boot_path "${path}"
        return 0
      fi
    done <<< "$(printf '%s\n' "${rpm_out}")"
  done

  if [[ -n "${GV_VMLINUZ_PREFIX}" ]]; then
    rpm_fb=$(rpm -qa 'kernel-core-*' 2>/dev/null | grep -F "${GV_VMLINUZ_PREFIX}" || true)
    while IFS= read -r n; do
      [[ -z "${n}" ]] && continue
      path="$(rpm -ql "$n" 2>/dev/null \
        | grep -E '^/boot/vmlinuz-' \
        | grep -Ev '\.(hmac|debug|gz)(\.|$)' \
        | head -n1 || true)"
      if [[ -n "${path:-}" ]]; then
        map_boot_path "${path}"
        return 0
      fi
    done <<< "$(printf '%s\n' "${rpm_fb}")"
  fi

  shopt -s nullglob
  last=""
  for p in "${BOOT_MOUNT}/vmlinuz-${GV_BOOT_TAG}"* "${BOOT_MOUNT}/vmlinuz-${GV_VMLINUZ_PREFIX}"*; do
    case "${p}" in *rescue* | *.hmac | *.debug) continue ;; esac
    [[ -e "${p}" ]] || continue
    last="${p}"
  done

  if [[ -z "${last}" ]]; then
    for p in "${BOOT_MOUNT}/vmlinuz-"*; do
      bn="${p#"${BOOT_MOUNT}"/vmlinuz-}"
      case "${bn}" in *rescue* | *.hmac | *.debug) continue ;; esac
      [[ -e "${p}" ]] || continue
      if [[ "${bn}" == "${GV_BOOT_TAG}"* || "${bn}" == "${GV_VMLINUZ_PREFIX}"* ]]; then
        last="${p}"
      fi
    done
  fi
  shopt -u nullglob

  if [[ -n "${last}" ]]; then
    printf '%s\n' "${last}"
    return 0
  fi
  return 1
}

# --- Tests --------------------------------------------------------------------

td="$(mktemp -d)"
trap 'rm -rf "${td}"' EXIT

specs=(
  kernel-5.14.0-427.42.1.el9_4
  kernel-core-5.14.0-427.42.1.el9_4
  kernel-modules-5.14.0-427.42.1.el9_4
  kernel-modules-core-5.14.0-427.42.1.el9_4
)

BOOT_TAG="5.14.0-427.42.1.el9_4.x86_64"
PREFIX_SCAN="5.14.0-427.42.1"

# Test 1: rpm -q fails; rpm -qa glob works; rpm -ql lists hmac before real vmlinuz.
(
  export KP_BOOT_MOUNT="${td}/t1/boot"
  mkdir -p "${KP_BOOT_MOUNT}"
  touch "${KP_BOOT_MOUNT}/vmlinuz-5.14.0-427.42.1.el9_4.x86_64"

  rpm() {
    case "$1" in
      -q)
        return 1
        ;;
      -qa)
        printf '%s\n' "kernel-core-5.14.0-427.42.1.el9_4.x86_64"
        ;;
      -ql)
        cat <<'EOF'
/boot/vmlinuz-5.14.0-427.42.1.el9_4.x86_64.hmac
/boot/vmlinuz-5.14.0-427.42.1.el9_4.x86_64
EOF
        ;;
      *)
        fail "unexpected rpm argv: $*"
        ;;
    esac
  }
  export -f rpm

  out="$(last_resort_resolve_vmlinuz "${BOOT_TAG}" "${PREFIX_SCAN}" "${specs[@]}")"
  want="${KP_BOOT_MOUNT}/vmlinuz-5.14.0-427.42.1.el9_4.x86_64"
  [[ "${out}" == "${want}" ]] || fail "test1 path: got ${out}, want ${want}"
)
pass "rpm qa + ql skips hmac; paths map into KP_BOOT_MOUNT"

# Test 2: RPM yields nothing usable; prefixed globs recover the right file.
(
  export KP_BOOT_MOUNT="${td}/t2/boot"
  mkdir -p "${KP_BOOT_MOUNT}"
  touch "${KP_BOOT_MOUNT}/vmlinuz-5.14.0-427.42.1.el9_4.x86_64"

  rpm() { return 1; }
  export -f rpm

  out="$(last_resort_resolve_vmlinuz "${BOOT_TAG}" "${PREFIX_SCAN}" "${specs[@]}")"
  want="${KP_BOOT_MOUNT}/vmlinuz-5.14.0-427.42.1.el9_4.x86_64"
  [[ "${out}" == "${want}" ]] || fail "test2 path: got ${out}, want ${want}"
)
pass "filesystem glob finds vmlinuz when RPM queries fail"

# Test 3: spec wildcards dead; kernel-core-* NevRA substring fallback finds ql output.
(
  export KP_BOOT_MOUNT="${td}/t3/boot"
  mkdir -p "${KP_BOOT_MOUNT}"
  touch "${KP_BOOT_MOUNT}/vmlinuz-5.14.0-427.42.1.el9_64.x86_64"

  rpm() {
    case "$1" in
      -q)
        return 1
        ;;
      -qa)
        if [[ "${2:-}" == 'kernel-core-*' ]]; then
          printf '%s\n' "kernel-core-5.14.0-427.42.1.el9_64.x86_64"
          return 0
        fi
        return 1
        ;;
      -ql)
        printf '%s\n' "/boot/vmlinuz-5.14.0-427.42.1.el9_64.x86_64"
        ;;
      *)
        fail "unexpected rpm argv: $*"
        ;;
    esac
  }
  export -f rpm

  out="$(last_resort_resolve_vmlinuz "${BOOT_TAG}" "${PREFIX_SCAN}" "${specs[@]}")"
  want="${KP_BOOT_MOUNT}/vmlinuz-5.14.0-427.42.1.el9_64.x86_64"
  [[ "${out}" == "${want}" ]] || fail "test3 path: got ${out}, want ${want}"
)

pass "kernel-core-* NevRA substring fallback resolves ql payloads"
