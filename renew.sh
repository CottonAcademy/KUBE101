#! /bin/sh

# Copyright 2020 The KUBE101 Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

BASE_FOLDER=$(
    cd "$(dirname "$0")"
    pwd
)

# KUBEADM_CMD=/usr/local/bin/kubeadm
# KUBECTL_CMD=/usr/local/bin/kubectl

KUBEADM_CMD=kubeadm
KUBECTL_CMD=kubectl

reloadKubeMasterProcs() {
    local component
    for component in ${@:-apiserver controller-manager scheduler}; do
        local proc=kube-$component
        (docker ps -af name=k8s_$proc* -q | xargs --no-run-if-empty docker rm -f) > /dev/null
        (crictl pods --name $proc* -q | xargs -I% --no-run-if-empty bash -c 'crictl stopp % && crictl rmp %') > /dev/null
    done
}

renewCerts() {
    local out=${BASE_FOLDER}/nohup.out
    rm -rf $out
    local crt
    for crt in ${@:-admin.conf apiserver apiserver-kubelet-client controller-manager.conf front-proxy-client scheduler.conf}; do
        echo "nohup $KUBEADM_CMD alpha certs renew $crt --use-api >> $out 2>&1 &" | sh
    done

    local csr_list csr_num
    for i in $(seq 1 30); do
        sleep 1
        csr_num=$(cat $out | grep '[certs]' | grep 'created' | wc -l)
        csr_list=$(cat $out | grep '[certs]' | grep 'created' | awk '{print $4}')
        if [ $csr_num -eq 6 ]; then
            echo $csr_list | xargs -n 1 $KUBECTL_CMD certificate approve
            break
        fi
    done
    reloadKubeMasterProcs
}

healthCheck() {
    for i in $(seq 1 30); do
        sleep 5
        $KUBECTL_CMD get node --kubeconfig=/etc/kubernetes/admin.conf
        if [ $? -eq 0 ]; then
            break
        fi
    done
}

renewCerts
healthCheck
