# SkarnOS Example

This directory contains an example flake which utilizes SkarnOS to deploy a simple 2 node kubernetes cluster. This flake is built using [blueprint](https://github.com/numtide/blueprint/). It contains two NixOS configurations [worker-1](./hosts/worker-1) and [controller-1](./hosts/controller-1) which together form a very basic Kubernetes cluster. The choice of CNI is `flannel`.

Each node's configuration directory (`./hosts/<node-name>`) contains:
- `./kubernetes.nix` - everything related to the Kubernetes cluster itself
- `./disko.nix` - partitioning information for fully automated installs
- `./configuration.nix` - core configuration, which ties everything together

## Development Shell

This example also includes a development shell which includes a few useful utilities, you can enter this shell by issuing the following command:

```bash
nix develop
```

## Using This Example as a Template

To create a new flake based on this example, issue the following command in a empty directory:

```bash
nix flake init -t github:SkarnOS/distro#
```

# Deploying a Cluster

You can deploy a cluster based on this example flake. This flake does make a few assumptions:
- we assume all your nodes are `x86_64-linux` machines
- we assume that all your nodes are Hetzner virtual machines
- we assume that all your nodes boot using UEFI

If you need to change any of these assumptions, you will have to dig into each `./hosts/<node>/disko.nix` and `./hosts/<node>/configuration.nix` files. You will want to swap the hardware module that is imported from SrvOS (or write your own) and change the partitioning and possibly the bootloader. The specifics on how to do this are out of scope for this README.

The only change you have to make, assuming all the assumptions hold, is to edit all `./hosts/<node>/kubernetes.nix` with the correct `sshTarget` value. It should be a `root@ip-address` (or `root@hostname`) string.

With everything above done, **you're ready to install SkarnOS**.

## Installing SkarnOS onto Servers

First things first, we need to install SkarnOS onto 2 servers, for which we'll utilize `nixos-anywhere`. You can run the following commands to do that:

> [!CAUTION]
>
> These commands WILL erase everything on the targets you provide, you have been WARNED!

```bash
skarnos install controller-1
skarnos install worker-1
```

After these two commands finish, you should be left with two SkarnOS servers, which do not yet form a cluster. To make that happen, run the following command:

```bash
skarnos join controller-1 worker-1
```

Now you should have a cluster, congratulations!

## Deploying to Your SkarnOS Servers

To deploy to your new servers, you can use the following command:

```bash
skarnos deploy ACTION controller-1 worker-1
```

**`ACTION`** can be one of the following:

- `test` will apply the new configuration only temporarily. Upon next reboot the server will rollback to the last permanently deployed configuration.
- `switch` will apply the new configuration permanently and immediately.
- `boot` will apply the new configuration permanently but will not make changes to the running system. The new configuration will take effect only after rebooting the server.
