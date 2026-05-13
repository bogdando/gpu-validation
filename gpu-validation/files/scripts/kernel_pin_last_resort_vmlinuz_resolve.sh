#!/usr/bin/env bash
# Last resort: derive a grubby-compatible vmlinuz path from RPM metadata + ${BOOT_MOUNT}/vmlinuz-*.
#
# Called from gpu-validation/tasks/kernel_pin.yaml via ansible.builtin.script (see KERNEL_* variables).
#
# Environment:
#   GV_BOOT_TAG                       profile boot string (uname -r target), trimmed
#   GV_VMLINUZ_PREFIX                  boot string with arch suffix stripped
#   KP_BOOT_MOUNT                      default /boot; use a fake root/boot for mocks/chroots
#   KERNEL_PIN_PACKAGES_B64            newline-separated RPM specs from pin profile (base64)
#   KERNEL_PIN_VMLINUZ_RESOLVE_DEBUG   when "1", print diagnostics to stderr on failure
#
# Exit codes: 0 success, 1 could not resolve, 2 invalid input (e.g. bad base64 / no specs)
set -euo pipefail

BOOT_MOUNT="${KP_BOOT_MOUNT:-/boot}"
GV_BOOT_TAG="${GV_BOOT_TAG:-}"
GV_VMLINUZ_PREFIX="${GV_VMLINUZ_PREFIX:-}"

debug_dump() {
  [[ "${KERNEL_PIN_VMLINUZ_RESOLVE_DEBUG:-}" == "1" ]] || return 0
  {
    printf 'kernel_pin_last_resort_vmlinuz_resolve: debug\n'
    printf 'BOOT_MOUNT=%q GV_BOOT_TAG=%q GV_VMLINUZ_PREFIX=%q\n' \
      "${BOOT_MOUNT}" "${GV_BOOT_TAG}" "${GV_VMLINUZ_PREFIX}"
    printf '\nls -la %q\n' "${BOOT_MOUNT}"
    ls -la "${BOOT_MOUNT}" 2>&1 || true
    printf '\nrpm -qa "kernel*"\n'
    rpm -qa 'kernel*' 2>&1 | head -200 || true
  } >&2
}

map_boot_path() {
  local fp="${1:?}"
  if [[ "${fp}" == /boot/* ]]; then
    printf '%s\n' "${BOOT_MOUNT}/${fp#/boot/}"
    return 0
  fi
  printf '%s\n' "${fp}"
}

vmlinuz_from_rpm_ql() {
  rpm -ql "$1" 2>/dev/null \
    | grep -E '^/boot/vmlinuz-' \
    | grep -Ev '\.(hmac|debug|gz)(\.|$)' \
    | head -n1 || true
}

emit_if_exists() {
  local path="${1:-}"
  [[ -n "${path}" ]] || return 1
  local mapped
  mapped="$(map_boot_path "${path}")"
  [[ -e "${mapped}" ]] || return 1
  printf '%s\n' "${mapped}"
  return 0
}

try_nevra_list() {
  local rpm_out="$1"
  local n path
  while IFS= read -r n; do
    [[ -z "${n}" ]] && continue
    path="$(vmlinuz_from_rpm_ql "${n}")"
    if emit_if_exists "${path}"; then
      return 0
    fi
  done <<< "$(printf '%s\n' "${rpm_out}")"
  return 1
}

if [[ -n "${KERNEL_PIN_PACKAGES_B64:-}" ]]; then
  specs="$(printf '%s' "${KERNEL_PIN_PACKAGES_B64}" | base64 -d 2>/dev/null || true)"
  if [[ -z "${specs}" ]]; then
    printf 'kernel_pin_last_resort_vmlinuz_resolve: could not decode KERNEL_PIN_PACKAGES_B64\n' >&2
    debug_dump
    exit 2
  fi
else
  specs="$(cat)"
fi

if [[ -z "$(printf '%s' "${specs}" | tr -d '[:space:]')" ]]; then
  printf 'kernel_pin_last_resort_vmlinuz_resolve: no package specs\n' >&2
  debug_dump
  exit 2
fi

while IFS= read -r spec || [[ -n "${spec}" ]]; do
  spec="${spec//$'\r'/}"
  spec="$(printf '%s' "${spec}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ -z "${spec}" ]] && continue

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
  if try_nevra_list "${rpm_out}"; then
    exit 0
  fi
done <<< "$(printf '%s\n' "${specs}")"

kcore_all="$(rpm -qa 'kernel-core-*' 2>/dev/null | sort -rV || true)"
if [[ -n "${kcore_all}" ]]; then
  rpm_fb=""
  if [[ -n "${GV_VMLINUZ_PREFIX}" ]]; then
    rpm_fb="$(printf '%s\n' "${kcore_all}" | grep -F "${GV_VMLINUZ_PREFIX}" || true)"
  fi
  if [[ -z "${rpm_fb}" && -n "${GV_BOOT_TAG}" ]]; then
    rpm_fb="$(printf '%s\n' "${kcore_all}" | grep -F "${GV_BOOT_TAG}" || true)"
  fi
  if [[ -z "${rpm_fb}" ]]; then
    rpm_fb="${kcore_all}"
  fi
  if try_nevra_list "${rpm_fb}"; then
    exit 0
  fi
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
  exit 0
fi

debug_dump
exit 1
