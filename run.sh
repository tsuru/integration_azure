#!/bin/bash

if [[ "$AZURE_CLIENT_ID" == "" ]] || 
    [[ "$AZURE_CLIENT_SECRET" == "" ]] || 
    [[ "$AZURE_SUBSCRIPTION_ID" == "" ]] || 
    [[ "$AZURE_TENANT_ID" == "" ]]; then
    echo "Missing required envs"
    exit 1
fi

export AZURE_RESOURCE_GROUP='docker-machine'
export AZURE_VIRTUAL_NETWORK='docker-machine-vnet'
export AZURE_SUBNET='docker-machine'
export AZURE_LOCATION="eastus"
export AZURE_AGENT_VM_SIZE="Standard_D1_v2"
export AZURE_AGENT_POOL_NAME="agentpool0"

set -e

TSURUVERSION=${TSURUVERSION:-latest}

echo "Going to test tsuru image version: $TSURUVERSION"

function abspath() { echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"; }
mypath=$(abspath $(dirname ${BASH_SOURCE[0]}))
finalconfigpath=$(mktemp)
installname=$(openssl rand -hex 4)
cp ${mypath}/config.yml ${finalconfigpath}
sed -i.bak "s,\$AZURE_CLIENT_ID,${AZURE_CLIENT_ID},g" ${finalconfigpath}
sed -i.bak "s,\$AZURE_CLIENT_SECRET,${AZURE_CLIENT_SECRET},g" ${finalconfigpath}
sed -i.bak "s,\$AZURE_SUBSCRIPTION_ID,${AZURE_SUBSCRIPTION_ID},g" ${finalconfigpath}
sed -i.bak "s,\$INSTALLNAME,int-${installname},g" ${finalconfigpath}
sed -i.bak "s,\$TSURUVERSION,${TSURUVERSION},g" ${finalconfigpath}

tmpdir=$(mktemp -d)
ssh-keygen -t rsa -N '' -f ${tmpdir}/clusterid
export AZURE_SSH_PUBLIC_KEY="$(cat ${tmpdir}/clusterid.pub)"

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

export TSURU_INTEGRATION_examplesdir="${GOPATH}/src/github.com/tsuru/platforms/examples"
export TSURU_INTEGRATION_installerconfig=${finalconfigpath}
export TSURU_INTEGRATION_nodeopts="iaas=dockermachine"
export TSURU_INTEGRATION_maxconcurrency=4
export TSURU_INTEGRATION_verbose=1
export TSURU_INTEGRATION_enabled=1
export TSURU_INTEGRATION_clusters="aks"

go test -v -count 1 -timeout 120m github.com/tsuru/tsuru/integration

rm -f ${finalconfigpath}
rm -rf "${tmpdir}"