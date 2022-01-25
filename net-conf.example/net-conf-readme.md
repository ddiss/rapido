This directory provides an example network configuration for rapido VMs.
It can be used as-is by running:

```console
myuser@computer:~/rapido$ cp -r net-conf.example net-conf
myuser@computer:~/rapido$ sudo tools/br_tap_setup.sh -o "myuser"
```

For details, see [configuration file comments](net-conf.example/vm1/rapido-tap1.network).
