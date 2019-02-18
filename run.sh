#!/bin/bash

[[ -f .env ]] && . .env

if [[ "$AZURE_CLIENT_ID" == "" ]] || 
    [[ "$AZURE_CLIENT_SECRET" == "" ]] || 
    [[ "$AZURE_SUBSCRIPTION_ID" == "" ]] || 
    [[ "$AZURE_TENANT_ID" == "" ]]; then
    echo "Missing required envs"
    exit 1
fi

function az_cleanup() {
    sudo apt-get install apt-transport-https lsb-release software-properties-common dirmngr -y
    AZ_REPO=$(lsb_release -cs)
    echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | \
        sudo tee /etc/apt/sources.list.d/azure-cli.list
    sudo apt-key --keyring /etc/apt/trusted.gpg.d/Microsoft.gpg adv \
        --keyserver packages.microsoft.com \
        --recv-keys BC528686B50D79E339D3721CEB3E94ADBE1229CF
    sudo apt-get update
    sudo apt-get install azure-cli -y
    az login --service-principal -u "$AZURE_CLIENT_ID" -p "$AZURE_CLIENT_SECRET" --tenant "$AZURE_TENANT_ID"
    az group delete -y --name docker-machine
}

export AZURE_RESOURCE_GROUP='docker-machine'
export AZURE_VIRTUAL_NETWORK='docker-machine-vnet'
export AZURE_SUBNET='docker-machine'
export AZURE_LOCATION="westus"
export AZURE_AGENT_VM_SIZE="Standard_D3_v2"
export AZURE_AGENT_POOL_NAME="agentpool0"

which apt-get && az_cleanup

set -e

TSURUVERSION=${TSURUVERSION:-latest}

echo "Going to test tsuru image version: $TSURUVERSION"

function abspath() { echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"; }
mypath=$(abspath $(dirname ${BASH_SOURCE[0]}))
finalconfigpath=$(mktemp)
installname="int-$(openssl rand -hex 4)"
cp ${mypath}/config.yml ${finalconfigpath}
sed -i.bak "s,\$AZURE_CLIENT_ID,${AZURE_CLIENT_ID},g" ${finalconfigpath}
sed -i.bak "s,\$AZURE_CLIENT_SECRET,${AZURE_CLIENT_SECRET},g" ${finalconfigpath}
sed -i.bak "s,\$AZURE_SUBSCRIPTION_ID,${AZURE_SUBSCRIPTION_ID},g" ${finalconfigpath}
sed -i.bak "s,\$INSTALLNAME,${installname},g" ${finalconfigpath}
sed -i.bak "s,\$TSURUVERSION,${TSURUVERSION},g" ${finalconfigpath}
sed -i.bak "s,\$AZURE_AGENT_VM_SIZE,${AZURE_AGENT_VM_SIZE},g" ${finalconfigpath}

tmpdir=$(mktemp -d)
ssh-keygen -t rsa -N '' -f ${tmpdir}/clusterid
export AZURE_SSH_PUBLIC_KEY="$(cat ${tmpdir}/clusterid.pub)"

if [ -z $USE_LOCAL_TSURU ]; then
    export GOPATH=${tmpdir}
    export PATH=$GOPATH/bin:$PATH
    echo "Go get platforms..."
    go get -d github.com/tsuru/platforms/examples/go
    echo "Go get tsuru..."
    go get github.com/tsuru/tsuru/integration

    echo "Go get tsuru client..."
    go get -d github.com/tsuru/tsuru-client/tsuru
    pushd $GOPATH/src/github.com/tsuru/tsuru-client
    if [ "$TSURUVERSION" != "latest" ]; then
    MINOR=$(echo "$TSURUVERSION" | sed -E 's/^[^0-9]*([0-9]+\.[0-9]+).*$/\1/g')
    CLIENT_TAG=$(git tag --list "$MINOR.*" --sort=-taggerdate | head -1)
    if [ "$CLIENT_TAG" != "" ]; then
        echo "Checking out tsuru-client $CLIENT_TAG"
        git checkout $CLIENT_TAG
    fi
    fi
    go install ./...
    popd
fi

export TSURU_INTEGRATION_installername="${installname}"
export TSURU_INTEGRATION_examplesdir="${GOPATH}/src/github.com/tsuru/platforms/examples"
export TSURU_INTEGRATION_installerconfig=${finalconfigpath}
export TSURU_INTEGRATION_nodeopts="iaas=dockermachine"
export TSURU_INTEGRATION_maxconcurrency=4
export TSURU_INTEGRATION_enabled=1
export TSURU_INTEGRATION_clusters="aks"
if [ -z $TSURU_INTEGRATION_verbose ]; then
  export TSURU_INTEGRATION_verbose=1
fi

go test -v -count 1 -timeout 120m github.com/tsuru/tsuru/integration

rm -f ${finalconfigpath}
rm -rf "${tmpdir}"