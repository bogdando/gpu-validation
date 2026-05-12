# gpu-validation

## Running from a crc hypervisor node
Once the RHOSO + RHEL AI setup is complete, do the following:

1. Clone the repository
    ```
    git clone git@github.com:rhos-vaf/gpu-validation.git
    cd gpu-validation/
    ```
1. (Optional - see NOTE below) Create a credentials file for registry login using a token. You can generate one at [here](https://access.redhat.com/terms-based-registry/) after logging in.

    NOTE - If not providing registry credentials, you must disable model tests with `-e gpu_validation_model_tests_enabled=false`

    creds.yaml
    ```
    gpu_validation_model_download_registry_username: "|3c5aa7e0-9bb9...."
    gpu_validation_model_download_registry_password: "eyJhbGciOiJSUzUxMiJ9...."
    ```
1. Set up and test your access to RHOSO
    ```
    oc cp openstackclient:.config/openstack/ ~/.config/openstack
    oc cp openstackclient:/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem ./tls-ca-bundle.pem
    export OS_CLOUD=default
    openstack --os-cacert ./tls-ca-bundle.pem flavor list
    ```
1. Install Ansible dependencies
    ```
    ansible-galaxy install -r requirements.yaml
    ```
1. Run it (requires ansible-core>=2.15)
    ```
    JUNIT_OUTPUT_DIR=./ ansible-playbook -i inventory main.yaml -e @vars.yaml -e @creds.yaml -e '{"gpu_validation_pci_devices":{"10de:20f1": 1}}'
    ```

### Optional: pin guest kernel before NVIDIA (Stream → RHEL 9.4 line)

Guests built from CentOS Stream often boot `5.14.0-700.el9` while EDPM computes use **`5.14.0-427*.el9_4`**,
so DKMS/kernel-devel mismatch breaks the GRID driver install. Enable the role task that aligns the VM kernel:

- Repos on the VM must actually ship the listed kernel RPMs (RHOSP tooling / entitlement channels), **or** use **AlmaLinux**/**Rocky Linux** Vault (below). **Never enable both vault flags** at once—the play fails fast if you do.
- `gpu_validation_pin_kernel_profiles` carries a **`9.4`** preset (matching the common hybrid stack); extend the map or pass explicit RPM lists **with dist tags that exist on your repos** — Alma often ships `…el9_4.alma.…`; Rocky publishes `…el9_4.rocky*` / `….el9.*rocky`; neither is byte‑identical to Red Hat-signed builds.

**CentOS Stream vs RHEL‑line kernels (no entitlement)** · short version:

| Source | Gives you `427*.el9_4`-style kernels to match RHOSP computes? |
|--------|----------------------------------------------------------------------|
| **CentOS Stream 9 repos** (`/centos/9-stream/…`) | **No** for the RH EUS lineage — Stream tracks a parallel `…el9` numbering (your `700` example). Same major `5.14`, different build stream. |
| **CentOS Sources** git + `rpmbuild` | Theoretically possible if you reconstruct the downstream tree—but you must redo packaging, `%dist`, ABI, signatures; operations-heavy compared to grabbing existing EL rebuild binaries. |
| **AlmaLinux / Rocky Vault** (`…/vault/<minor>/…`) | **Yes-ish** · FREE EL-rebuild lineage. Enable **`gpu_validation_pin_kernel_almalinux_vault_enable`** *or* **`gpu_validation_pin_kernel_rocky_vault_enable`** (mutually exclusive) |

Automatic **AlmaLinux** vault wiring (imports Alma GPG key and enables BaseOS/AppStream vault for `gpu_validation_pin_kernel_almalinux_vault_minor`, default **`9.4`**):

```
ansible-playbook -i inventory main.yaml \
  -e gpu_validation_pin_kernel_enabled=true \
  -e gpu_validation_pin_kernel_almalinux_vault_enable=true \
  -e '{"gpu_validation_pin_kernel_rhel_release":"9.4"}'
```

Automatic **Rocky Linux** vault wiring (respects `gpu_validation_pin_kernel_rocky_vault_minor`, default **`9.4`**, GPG key configurable via `gpu_validation_pin_kernel_rocky_vault_gpg_url`):

```
ansible-playbook -i inventory main.yaml \
  -e gpu_validation_pin_kernel_enabled=true \
  -e gpu_validation_pin_kernel_rocky_vault_enable=true \
  -e '{"gpu_validation_pin_kernel_rhel_release":"9.4"}'
```

Discover published **Alma** nevRAs:

```
sudo dnf --disablerepo='*' --enablerepo='gpu-val-alma-vault-baseos' --enablerepo='gpu-val-alma-vault-appstream' \
  repoquery 'kernel*427*'
```

Discover published **Rocky** nevRAs:

```
sudo dnf --disablerepo='*' --enablerepo='gpu-val-rocky-vault-baseos' --enablerepo='gpu-val-rocky-vault-appstream' \
  repoquery 'kernel*427*'
```

**Caveat**: Installing signed **kernel\* RPMs onto a CentOS Stream root filesystem** mixes distros—you may need manual dependency fixes. Safest ergonomics remain a **matching EL cloud image**.


Ad-hoc run (facts must report `distribution_version` `9.4`, or force the profile key explicitly):

```
ansible-playbook -i inventory main.yaml \
  -e gpu_validation_pin_kernel_enabled=true \
  -e '{"gpu_validation_pin_kernel_rhel_release":"9.4"}'
```

CentOS Stream images sometimes expose `distribution_version: "9"` — in that case always set **`gpu_validation_pin_kernel_rhel_release`** to **`9.4`** after enabling repos that supply the **`427*`** kernels.

Custom NEVRA list (+ exact `uname -r` target):

```
ansible-playbook -i inventory main.yaml \
  -e gpu_validation_pin_kernel_enabled=true \
  -e gpu_validation_pin_kernel_boot=5.14.0-427.13.1.el9_4.x86_64 \
  -e '{"gpu_validation_pin_kernel_packages":["kernel-5.14.0-427.13.1.el9_4",...]}' \
  -e '{"gpu_validation_pin_kernel_devel_packages":["kernel-devel-5.14.0-427.13.1.el9_4",...]}'
```

## Running w/ test-operator

1. Confirm that your RHOSO deployment has test-operator running
    ```
    $ oc get deploy -n openstack-operators test-operator-controller-manager
    NAME                               READY   UP-TO-DATE   AVAILABLE   AGE
    test-operator-controller-manager   1/1     1            1           29d
    ```
1. Adjust the `gpu_validation_pci_devices` variable in AnsibleTestCR.yaml to match your hardware
1. Launch the test container
    ```
    $ oc apply -f AnsibleTestCR.yaml
    ```
