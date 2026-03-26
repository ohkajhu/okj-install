#!/bin/bash
# set -e

echo "Disabling swap..."
sudo swapoff -a
echo "Removing swap entry from /etc/fstab..."
sudo sed -i '/ swap /d' /etc/fstab

# Check for missing packages
missing=""
! command -v openssl >/dev/null 2>&1 && missing+=" openssl"
! command -v chronyc >/dev/null 2>&1 && missing+=" chrony"

if [ -n "$missing" ]; then
    echo "Installing missing packages:$missing"
    sudo apt-get update -qq
    sudo apt-get install -y $missing
else
    echo "Both openssl and chrony are already installed."
fi

# Create the K3s configuration directory if it doesn't exist
sudo mkdir -p /etc/rancher/k3s

# Create the registries.yaml file with the mirror configuration
sudo tee /etc/rancher/k3s/registries.yaml <<EOF
mirrors:
  "docker.io":
    endpoint:
      - "https://mirror.gcr.io"
EOF

DOWNLOAD_URL="https://storage.googleapis.com/ttm-infra-public/k3s"

wget -q $DOWNLOAD_URL/k3s-1326 -O /usr/local/bin/k3s
# source: https://github.com/k3s-io/k3s/blob/master/install.sh
wget -q $DOWNLOAD_URL/k3s-install.sh  -O /usr/local/bin/k3s-install.sh
wget -q $DOWNLOAD_URL/generate-custom-ca-certs.sh -O /usr/local/bin/generate-custom-ca-certs.sh
wget -q $DOWNLOAD_URL/kubectl -O /usr/local/bin/kubectl_
chmod 755 /usr/local/bin/k3s /usr/local/bin/k3s-install.sh /usr/local/bin/generate-custom-ca-certs.sh /usr/local/bin/kubectl_

export INSTALL_K3S_SKIP_START=true
export INSTALL_K3S_SKIP_DOWNLOAD="true"
export INSTALL_K3S_EXEC="--disable=traefik --cluster-cidr=10.96.0.0/16 --service-cidr=10.69.0.0/16"
# Install K3s Clsuter
/usr/local/bin/k3s-install.sh &> /dev/null

echo "100 years CA certificate generation..."
/usr/local/bin/generate-custom-ca-certs.sh &>/dev/null

#### DOCKER_MIRROR_URL="http://docker-registry-mirror.home.net"
#### mkdir -p /etc/rancher/k3s
#### cat <<EOF | tee /etc/rancher/k3s/registries.yaml > /dev/null
#### mirrors:
####   "docker.io":
####     endpoint:
####       - "$DOCKER_MIRROR_URL"
#### EOF

systemctl restart k3s
sleep 3

systemctl stop chrony

for i in $(seq 1 3); do
 date -s "+364 days" &>/dev/null
 k3s certificate rotate &>/dev/null
 systemctl restart k3s
 sleep 3
done
#### ntpdate time.google.com &>/dev/null

systemctl restart chrony
chronyc -a makestep
systemctl restart k3s
systemctl status k3s --no-pager | head -12
k3s certificate check --output table | grep -v "a long while"| head -8
#####

rm -rf /usr/local/bin/kubectl
cd /usr/local/bin
mv kubectl_ kubectl
ln -s kubectl k
mkdir $HOME/.kube
k3s kubectl config view  --raw | sed  "s/127\.0\.0\.1/$(hostname -I|awk {'print $1'})/g"  > $HOME/.kube/config
chmod 600 $HOME/.kube/config
echo ""
#### cat $HOME/.kube/config
echo ""

echo -n "Waiting for k3s components running"
while true; do
  count=$(crictl ps | grep Running | wc -l)
  if [ "$count" -ge 3 ]; then
    break
  fi
  echo -n "."
  sleep 5
done
echo ""

echo ""
k rollout restart deployment  -n kube-system
sleep 1
kubectl wait -n kube-system pod -l k8s-app=kube-dns --for=condition=ready --timeout=60s &> /dev/null
k get node -o wide
echo ""
k get pod -A
echo ""

echo ""
date
echo ""
echo "source <(kubectl completion bash) ;complete -F __start_kubectl k"
echo ""

kubectl get configmap coredns -n kube-system -o json | \
jq --arg ip1 "125.254.54.194" '
  .data.NodeHosts |= (
    split("\n")
    | map(select(length > 0))
    | map(select(
        (test("registry\\.ohkajhu\\.com") | not) and
        (test("shop-gateway\\.ohkajhu\\.com") | not)
      ))
    + [
        "\($ip1) registry.ohkajhu.com",
        "\($ip1) shop-gateway.ohkajhu.com"
      ]
    | join("\n")
  )
' | kubectl apply -f -

echo "apply net host"