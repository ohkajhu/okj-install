#!/bin/bash

set -e

# ตรวจสอบว่าคำสั่ง k3s และ kubectl ใช้งานได้หรือไม่
if ! command -v k3s >/dev/null 2>&1; then
    echo "🚨 Error: k3s command not found. Please ensure k3s is installed correctly."
    exit 1
fi

echo "================================================================="
echo "        K3s IP Change & Certificate Recovery Script              "
echo "================================================================="

# --- 1. Fix: แก้ไข IP ใน Kubeconfig ---
echo "⚙️  1. Updating Kubeconfig (Fixing IP change)..."
NEW_IP=$(hostname -I | awk '{print $1}')
echo "   - Current Node IP detected: $NEW_IP"

# ใช้ k3s config view เพื่อดึง config ล่าสุด และแทนที่ 127.0.0.1 ด้วย IP ใหม่
k3s kubectl config view --raw | sed "s/127\.0\.0\.1/$NEW_IP/g" > $HOME/.kube/config

if [ $? -eq 0 ]; then
    chmod 600 $HOME/.kube/config
    echo "   ✅ Kubeconfig updated successfully at $HOME/.kube/config."
else
    echo "   ❌ Failed to update Kubeconfig. Exiting."
    exit 1
fi
echo ""

# --- 2. Fix: หมุนเวียน Certificate ---
echo "📜  2. Attempting Certificate Rotation..."
echo "   - Stopping k3s service..."
sudo systemctl stop k3s

# สั่งหมุนเวียน Certificate. K3s จะสร้างไฟล์ Cert ใหม่
if sudo k3s certificate rotate; then
    echo "   ✅ Certificates rotated successfully."
else
    echo "   ❌ Failed to execute k3s certificate rotate. Check k3s logs."
fi

echo "   - Starting k3s service and waiting 15 seconds for components to stabilize..."
sudo systemctl start k3s
sleep 15
echo ""

# ตรวจสอบสถานะ Certificate หลังการหมุน
echo "🔍 Checking new certificate status:"
sudo k3s certificate check --output table | grep -v "a long while" | head -8
echo ""


# --- 3. Fix: Re-apply CoreDNS Custom Host Entries (ตามสคริปต์เดิม) ---
echo "🔄  3. Re-applying CoreDNS custom host entries..."

# ตรวจสอบและติดตั้ง jq หากยังไม่มี (จำเป็นสำหรับการแก้ไข ConfigMap)
if ! command -v jq >/dev/null 2>&1; then
    echo "   ⚠️ jq is not installed. Installing jq (required for CoreDNS fix)..."
    sudo apt-get update -qq
    sudo apt-get install -y jq
    if [ $? -ne 0 ]; then
        echo "   ❌ Failed to install jq. Skipping CoreDNS fix. Please install jq manually."
    fi
fi

# ใช้ jq เพื่อปรับปรุง CoreDNS ConfigMap โดยการเพิ่ม/แก้ไข custom hosts
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

if [ $? -eq 0 ]; then
    echo "   ✅ CoreDNS ConfigMap updated successfully."
else
    echo "   ❌ Failed to update CoreDNS ConfigMap."
fi
echo ""

# --- 4. Verification: ตรวจสอบสถานะโดยรวม ---
echo "✅  4. Final Verification and component restart..."

# สั่ง rollout restart เพื่อให้ CoreDNS และ Components อื่นๆ โหลด config ใหม่
kubectl rollout restart deployment -n kube-system

echo "   - Waiting up to 90s for CoreDNS to become ready..."
# รอจนกว่า CoreDNS จะพร้อม (ใช้เวลาหลังจาก rollout)
kubectl wait -n kube-system pod -l k8s-app=kube-dns --for=condition=ready --timeout=90s

echo ""
echo "================================================================="
echo "                    RECOVERY COMPLETE                            "
echo "================================================================="

echo "➡️  Node Status:"
kubectl get node -o wide

echo ""
echo "➡️  Pods Status:"
kubectl get pod -A

echo ""
echo "Run 'source <(kubectl completion bash) ;complete -F __start_kubectl k' to re-enable command completion."