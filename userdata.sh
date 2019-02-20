#!/bin/bash

# Why is this here? Azure is weird, *very* frequently docker-machine will fail
# to provision the machine when running `apt-get update` using ssh. An example
# of the error messages returned are:
#
# https://circleci.com/gh/tsuru/integration_azure/26:
# ```
# E: can not open /var/lib/apt/lists/archive.ubuntu.com_ubuntu_dists_bionic_InRelease - fopen (2: No such file or directory)
# E: The repository 'http://archive.ubuntu.com/ubuntu bionic InRelease' provides only weak security information.
# ```
#
# https://circleci.com/gh/tsuru/integration_azure/24 and
# https://circleci.com/gh/tsuru/integration_azure/23:
# ```
# W: GPG error: http://archive.ubuntu.com/ubuntu bionic InRelease: Splitting up /var/lib/apt/lists/archive.ubuntu.com_ubuntu_dists_bionic_InRelease into data and signature failed
# E: The repository 'http://archive.ubuntu.com/ubuntu bionic InRelease' is not signed.
# ```
#
# I don't know exactly what's going on, but it looks like something is messing
# with apt repositories right after boot. This userdata script is a last resort
# attempt on trying to delay this mess until the machines are correctly
# provisioned.
#
echo "Running user data script..."
sleep 120
echo "Done user data script."
