<h1 align="center"><b>SkarnOS</b></h1>

<p align="center"><b>is a joint project between Numtide and Helsinki Systems</b></p>

> [!WARNING]
> Here be dragons!
>
> SkarnOS is very much work in progress and isn't ready yet for production use. Use it only if want to be part of it's development.

## What is SkarnOS

SkarnOS is to be a distribution of GNU+Linux based on [NixOS](https://nixos.org), catered to the operation of Kubernetes clusters. It provides a opinionated version of NixOS with some customizability allowing you to tweak and tune certain aspects. It is not meant to be a general purpose GNU+Linux distribution or a general purpose cluster distribution. It is solely focused on supporting Kubernetes deployments and occupies the same space as [Amazon's Bottlerocket](https://bottlerocket.dev) and [Flatcar](https://flatcar.org).

## Kubernetes Support

We aim to support all non-End-of-Life Kubernetes releases. The current supported releases can be found in [`./packages/sources.json`](./packages/sources.json).

## Usage

Currently to use SkarnOS, you must bring your own NixOS installation, SkarnOS has no installer *yet*. We recommend these tools/projects:
1. [SrvOS](https://github.com/nix-community/srvos) - NixOS profiles for servers
2. [disko](https://github.com/nix-community/disko) - Declarative disk partitioning and formatting using nix
3. [nixos-anywhere](https://github.com/nix-community/nixos-anywhere) - Install NixOS everywhere via SSH
4. [impermanence](https://github.com/nix-community/impermanence) or [preservation](https://github.com/nix-community/preservation) - Nix tooling to enable declarative management of non-volatile system state
5. [flake-parts](https://github.com/hercules-ci/flake-parts), [blueprint](https://github.com/numtide/blueprint/) or just [flake-utils](https://github.com/numtide/flake-utils) - Flake organization libraries

### Example

We have also put together an example flake to showcase how we would assemble such a flake, go to [`./example`](./example) and get inspired. All the code under [`./example`](./example) is licensed under the [Unlicense](https://unlicense.org/). Feel
free to use the [`./example`](./example) as a template for your own repository.

## Repository Structure

The repository is structured as such:
- [`./checks/kubernetes.nix`](./checks/kubernetes.nix)

  contains a NixOS VM test which tests the setup of a single-node Kubernetes cluster.
- [`./modules/nixos/kubernetes`](./modules/nixos/kubernetes)

  contains a actively developed set of NixOS modules which are the functional bits of SkarnOS.
- [`./packages`](./packages)

  contains Kubernetes packages and various supporting container images, along with a updater script which can be used to automatically update everything.

# Contributing

Even though this project is an early prototype, contributions are already welcome. We want to develop this in public from the early days. Currently what we would appreciate most is help with cleaning up the NixOS modules, they contain a lot of commented out code, which needs to be either uncommented and tested or dropped.
