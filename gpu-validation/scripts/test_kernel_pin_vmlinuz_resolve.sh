#!/usr/bin/env bash
#
# Regression tests for gpu-validation/files/scripts/kernel_pin_last_resort_vmlinuz_resolve.sh
# (invoked from gpu-validation/tasks/kernel_pin.yml via ansible.builtin.script).
#
# Run from anywhere:
#   bash gpu-validation/scripts/test_kernel_pin_vmlinuz_resolve.sh
set -euo pipefail

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'OK: %s\n' "$1"
}

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROLE_ROOT="$(cd "${HERE}/.." && pwd)"
RESOLVER="${ROLE_ROOT}/files/scripts/kernel_pin_last_resort_vmlinuz_resolve.sh"

[[ -x "${RESOLVER}" || -r "${RESOLVER}" ]] || fail "missing resolver at ${RESOLVER}"

b64_specs() {
  printf '%s\n' "$@" | base64 | tr -d '\n'
}

run_resolver_env() {
  local boot_tag="${1:?}"
  local vmlinuz_prefix="${2:?}"
  local boot_mount="${3:?}"
  shift 3
  export GV_BOOT_TAG="${boot_tag}"
  export GV_VMLINUZ_PREFIX="${vmlinuz_prefix}"
  export KP_BOOT_MOUNT="${boot_mount}"
  export KERNEL_PIN_PACKAGES_B64
  KERNEL_PIN_PACKAGES_B64="$(b64_specs "$@")"
  unset KERNEL_PIN_VMLINUZ_RESOLVE_DEBUG || true
  bash "${RESOLVER}"
}

specs=(
  kernel-5.14.0-427.42.1.el9_4
  kernel-core-5.14.0-427.42.1.el9_4
  kernel-modules-5.14.0-427.42.1.el9_4
  kernel-modules-core-5.14.0-427.42.1.el9_4
)

BOOT_TAG="5.14.0-427.42.1.el9_4.x86_64"
PREFIX_SCAN="5.14.0-427.42.1"

td="$(mktemp -d)"
trap 'rm -rf "${td}"' EXIT

(
  boot="${td}/t1/boot"
  mkdir -p "${boot}"
  touch "${boot}/vmlinuz-5.14.0-427.42.1.el9_4.x86_64"

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
        fail "test1 unexpected rpm argv: $*"
        ;;
    esac
  }
  export -f rpm

  out="$(run_resolver_env "${BOOT_TAG}" "${PREFIX_SCAN}" "${boot}" "${specs[@]}")"
  want="${boot}/vmlinuz-5.14.0-427.42.1.el9_4.x86_64"
  [[ "${out}" == "${want}" ]] || fail "test1 path: got ${out}, want ${want}"
)
pass "script: rpm qa + ql skips hmac; requires on-disk vmlinuz"

(
  boot="${td}/t2/boot"
  mkdir -p "${boot}"
  touch "${boot}/vmlinuz-5.14.0-427.42.1.el9_4.x86_64"

  rpm() { return 127; }
  export -f rpm

  out="$(run_resolver_env "${BOOT_TAG}" "${PREFIX_SCAN}" "${boot}" "${specs[@]}")"
  want="${boot}/vmlinuz-5.14.0-427.42.1.el9_4.x86_64"
  [[ "${out}" == "${want}" ]] || fail "test2 path: got ${out}, want ${want}"
)
pass "script: filesystem glob succeeds when RPM fails"

(
  boot="${td}/t3/boot"
  mkdir -p "${boot}"
  touch "${boot}/vmlinuz-5.14.0-427.42.1.el9_64.x86_64"

  rpm() {
    case "$1" in
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
      -q)
        return 1
        ;;
      *)
        fail "test3 unexpected rpm argv: $*"
        ;;
    esac
  }
  export -f rpm

  out="$(run_resolver_env "${BOOT_TAG}" "${PREFIX_SCAN}" "${boot}" "${specs[@]}")"
  want="${boot}/vmlinuz-5.14.0-427.42.1.el9_64.x86_64"
  [[ "${out}" == "${want}" ]] || fail "test3 path: got ${out}, want ${want}"
)
pass "script: scans kernel-core-* when substring filters fall back to full list"

(
  boot="${td}/t4/boot"
  mkdir -p "${boot}"
  touch "${boot}/vmlinuz-5.14.0-427.42.1.el9_4.x86_64"

  rpm() {
    case "$1" in
      -q)
        return 1
        ;;
      -qa)
        printf '%s\n' "kernel-core-5.14.0-427.42.1.el9_4.x86_64"
        ;;
      -ql)
        printf '%s\n' "/boot/vmlinuz-5.14.0-427.42.1.el9_4.x86_64"
        ;;
      *)
        fail "test4 unexpected rpm argv: $*"
        ;;
    esac
  }
  export -f rpm

  export GV_BOOT_TAG="${BOOT_TAG}"
  export GV_VMLINUZ_PREFIX="${PREFIX_SCAN}"
  export KP_BOOT_MOUNT="${boot}"
  export KERNEL_PIN_PACKAGES_B64
  KERNEL_PIN_PACKAGES_B64="$(printf '%s\n' "${specs[@]}" | base64 | tr -d '\n')"
  out="$(bash "${RESOLVER}")"
  want="${boot}/vmlinuz-5.14.0-427.42.1.el9_4.x86_64"
  [[ "${out}" == "${want}" ]] || fail "test4 path: got ${out}, want ${want}"
)
pass "script: KERNEL_PIN_PACKAGES_B64 decodes multi-line specs"
