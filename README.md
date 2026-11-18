# gpu-validation

## Running manually
Once the RHOSO setup is complete, do the following:

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

    NOTE - To verify the GPU survives guest reboots, enable the reboot stability
    loop with `-e gpu_validation_stability_tests_enabled=true`
    (optionally `-e gpu_validation_stability_cycles=N`, default 3). Each
    cycle reboots the guest and re-asserts the GPU (lspci, nvidia-smi, CUDA) with
    an informational dmesg scan. Off by default; needs a remote target (not
    local-runner mode).

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

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidelines and DCO information.

