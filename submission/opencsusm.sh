#!/usr/bin/env bash
# OpenCSUSM45567 - CS 446. Run locally: bash opencsusm.sh <1-8>.
# Stages 3/4 run on the instance through SSH; stage 6 runs on your laptop.
set -euo pipefail
export MSYS_NO_PATHCONV=1 AWS_PAGER=""
export AWS_PROFILE="${AWS_PROFILE:-opencsusm}"
# cpu: a 0.5B greeting needs no GPU. G quota=0; Standard quota=32.
# Free-plan workaround authorized by the user: c7i-flex.large + Ollama.
# The PDF's c7i.2xlarge was rejected as not Free Tier eligible.
# c7i-flex.large has 2 vCPUs/4 GiB, enough for the same 0.5B greeting test.
LANE=cpu
TYPE=c7i-flex.large
MODEL=qwen2.5:0.5b
REGION=us-east-1
PORT=11434
LOCAL_PORT="${LOCAL_PORT:-11434}"
NAME=opencsusm45567-20261011
KEYNAME="$NAME"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
STATE="$SCRIPT_DIR/.opencsusm-state"
KEY="$STATE/$KEYNAME.pem"
# Official 0.49B Qwen model, pinned Hugging Face revision and checksum.
HF_REPO=Qwen/Qwen2.5-0.5B-Instruct-GGUF
HF_REV=9217f5db79a29953eb74d5343926648285ec7e67
HF_FILE=qwen2.5-0.5b-instruct-q4_k_m.gguf
HF_SHA256=74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db
aws() { command aws --region "$REGION" "$@" | tr -d '\r'; }
iid() {
    aws ec2 describe-instances --filters "Name=tag:Name,Values=$NAME" \
        "Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down" \
        --query 'Reservations[].Instances[].InstanceId' --output text
}
dns() {
    aws ec2 describe-instances --filters "Name=tag:Name,Values=$NAME" "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' --output text
}
on_box() {
    local host; host=$(dns)
    [[ -n "$host" && "$host" != None ]] || { echo 'No running project instance.' >&2; return 1; }
    ssh -i "$KEY" -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
        -o "UserKnownHostsFile=$STATE/known_hosts" "ubuntu@$host" "$@"
}
cleanup() {
    local ids sg keys volumes remaining attempt
    ids=$(iid)
    if [[ -n "$ids" ]]; then
        aws ec2 terminate-instances --instance-ids $ids >/dev/null
        aws ec2 wait instance-terminated --instance-ids $ids
    fi
    volumes=$(aws ec2 describe-volumes --filters "Name=tag:Name,Values=$NAME" --query 'Volumes[].VolumeId' --output text)
    for volume in $volumes; do
        aws ec2 wait volume-available --volume-ids "$volume"
        aws ec2 delete-volume --volume-id "$volume" >/dev/null
        aws ec2 wait volume-deleted --volume-ids "$volume"
    done
    sg=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$NAME" --query 'SecurityGroups[].GroupId' --output text)
    for group in $sg; do
        for attempt in {1..12}; do
            if aws ec2 delete-security-group --group-id "$group" > /dev/null 2>"$STATE/delete-sg-error.log"; then break; fi
            if [[ "$attempt" == 12 ]]; then cat "$STATE/delete-sg-error.log" >&2; return 1; fi
            sleep 5
        done
    done
    keys=$(aws ec2 describe-key-pairs --filters "Name=key-name,Values=$KEYNAME" --query 'KeyPairs[].KeyName' --output text)
    for key_name in $keys; do aws ec2 delete-key-pair --key-name "$key_name" >/dev/null; done
    rm -f -- "$KEY"
    ids=$(iid)
    volumes=$(aws ec2 describe-volumes --filters "Name=tag:Name,Values=$NAME" --query 'Volumes[].VolumeId' --output text)
    sg=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$NAME" --query 'SecurityGroups[].GroupId' --output text)
    keys=$(aws ec2 describe-key-pairs --filters "Name=key-name,Values=$KEYNAME" --query 'KeyPairs[].KeyName' --output text)
    remaining="$ids$volumes$sg$keys"
    # Empty output is proof ONLY when all queries succeed and return no resources.
    if [[ -n "${remaining//[$'\n\t\r ']/}" ]]; then printf '%s\n' "$remaining"; return 1; fi
}
mkdir -p "$STATE"
chmod 700 "$STATE"
case "${1:-}" in
1)
    # First, quotas. No GPU quota increase is needed for the CPU lane.
    for quota in L-DB2E81BA L-1216C47A; do
        aws service-quotas get-service-quota --service-code ec2 --quota-code "$quota" \
            --query '{quota:Quota.QuotaName,value:Quota.Value}' --output table
    done
    echo "lane=$LANE type=$TYPE model=$MODEL"
    aws pricing get-products --service-code AmazonEC2 --filters \
        "Type=TERM_MATCH,Field=instanceType,Value=$TYPE" \
        'Type=TERM_MATCH,Field=location,Value=US East (N. Virginia)' \
        'Type=TERM_MATCH,Field=operatingSystem,Value=Linux' \
        'Type=TERM_MATCH,Field=tenancy,Value=Shared' \
        'Type=TERM_MATCH,Field=preInstalledSw,Value=NA' \
        'Type=TERM_MATCH,Field=capacitystatus,Value=Used' \
        --query PriceList --output text | grep -o '\$[0-9.]* per On Demand [^"]*' | sort -u
    ;;
2)
    [[ -z "$(iid)" ]] || { echo 'Project instance exists; refusing a duplicate.' >&2; exit 1; }
    [[ -z "$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$NAME" --query 'SecurityGroups[].GroupId' --output text)" ]] || { echo 'Project group exists; run stage 8 first.' >&2; exit 1; }
    [[ -z "$(aws ec2 describe-key-pairs --filters "Name=key-name,Values=$KEYNAME" --query 'KeyPairs[].KeyName' --output text)" ]] || { echo 'Project key exists; run stage 8 first.' >&2; exit 1; }
    trap 'result=$?; if (( result != 0 )); then echo "Stage 2 failed; cleaning project resources." >&2; bash "$SCRIPT_DIR/opencsusm.sh" 8 || echo "CLEANUP FAILED: run stage 8 immediately." >&2; fi; exit "$result"' EXIT
    aws ec2 create-key-pair --key-name "$KEYNAME" \
        --tag-specifications "ResourceType=key-pair,Tags=[{Key=Name,Value=$NAME},{Key=Course,Value=CS446}]" \
        --query KeyMaterial --output text >"$KEY"
    chmod 400 "$KEY"
    MYIP=$(curl -fsS --max-time 30 https://checkip.amazonaws.com | tr -d '\r\n')
    [[ "$MYIP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'IPv4 lookup failed.' >&2; exit 1; }
    VPC=$(aws ec2 describe-vpcs --filters Name=is-default,Values=true --query 'Vpcs[0].VpcId' --output text)
    [[ -n "$VPC" && "$VPC" != None ]] || { echo 'No default VPC; no VPC was created.' >&2; exit 1; }
    SG=$(aws ec2 create-security-group --group-name "$NAME" --vpc-id "$VPC" \
        --description 'CS446: SSH from owner IPv4 only; inference stays private' \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=$NAME},{Key=Course,Value=CS446}]" \
        --query GroupId --output text)
    # The ONLY inbound rule: SSH from your current IPv4 /32.
    aws ec2 authorize-security-group-ingress --group-id "$SG" --protocol tcp --port 22 --cidr "$MYIP/32" >/dev/null
    AMI=$(aws ssm get-parameter --name /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id \
        --query Parameter.Value --output text)
    # Emergency one-hour stop; stage 8 must still remove the disk afterward.
    printf '#!/bin/sh\nshutdown -P +60\n' >"$STATE/user-data.sh"
    USER_DATA_FILE="$STATE/user-data.sh"
    if command -v cygpath >/dev/null 2>&1; then USER_DATA_FILE=$(cygpath -m "$USER_DATA_FILE"); fi
    ID=$(aws ec2 run-instances --image-id "$AMI" --instance-type "$TYPE" --count 1 \
        --key-name "$KEYNAME" --security-group-ids "$SG" --associate-public-ip-address \
        --metadata-options HttpTokens=required,HttpEndpoint=enabled --user-data "file://$USER_DATA_FILE" \
        --block-device-mappings 'DeviceName=/dev/sda1,Ebs={VolumeSize=20,VolumeType=gp3,DeleteOnTermination=true,Encrypted=true}' \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$NAME},{Key=Course,Value=CS446}]" \
            "ResourceType=volume,Tags=[{Key=Name,Value=$NAME},{Key=Course,Value=CS446}]" \
        --query 'Instances[0].InstanceId' --output text)
    printf '%s\n' "$ID" >"$STATE/instance-id"
    aws ec2 wait instance-status-ok --instance-ids "$ID"
    echo "ssh -i '$KEY' ubuntu@$(dns)"
    trap - EXIT
    ;;
3)
    on_box 'bash -se' <<'REMOTE'
set -euo pipefail
curl -fsSL --retry 3 https://ollama.com/install.sh -o /tmp/install-ollama.sh
sudo sh /tmp/install-ollama.sh
sudo mkdir -p /etc/systemd/system/ollama.service.d
printf '[Service]\nEnvironment="OLLAMA_HOST=127.0.0.1:11434"\n' | sudo tee /etc/systemd/system/ollama.service.d/loopback.conf >/dev/null
sudo systemctl daemon-reload
sudo systemctl restart ollama
for attempt in {1..60}; do
    if curl -fsS http://127.0.0.1:11434/api/version; then exit 0; fi
    sleep 2
done
exit 1
REMOTE
    ;;
4)
    on_box 'bash -se' <<REMOTE
set -euo pipefail
mkdir -p ~/opencsusm-model
cd ~/opencsusm-model
curl -fL --retry 3 'https://huggingface.co/$HF_REPO/resolve/$HF_REV/$HF_FILE?download=true' -o '$HF_FILE'
echo '$HF_SHA256  $HF_FILE' | sha256sum -c -
printf 'FROM ./$HF_FILE\nPARAMETER num_ctx 2048\n' >Modelfile
ollama create '$MODEL' -f Modelfile
ollama list
curl -fsS http://127.0.0.1:$PORT/api/tags
ss -ltn | grep '127.0.0.1:$PORT'
REMOTE
    ;;
5)
    printf "ssh -i '%s' -o ExitOnForwardFailure=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile='%s/known_hosts' -N -L 127.0.0.1:%s:127.0.0.1:%s ubuntu@%s\n" "$KEY" "$STATE" "$LOCAL_PORT" "$PORT" "$(dns)"
    ;;
6)
    # Run only after the SSH tunnel is listening. Never use a local model as EC2 proof.
    curl --fail-with-body --silent --show-error --max-time 180 \
        "http://127.0.0.1:$LOCAL_PORT/v1/chat/completions" -H 'Content-Type: application/json' \
        -d '{"model":"qwen2.5:0.5b","messages":[{"role":"user","content":"I am John"}],"max_tokens":20,"temperature":0}'
    echo
    ;;
7)
    ID=$(iid)
    if [[ -n "$ID" ]]; then
        aws ec2 stop-instances --instance-ids $ID >/dev/null
        aws ec2 wait instance-stopped --instance-ids $ID
    fi
    ;;
8) cleanup ;;
*) echo 'usage: bash opencsusm.sh <1-8>' >&2; exit 1 ;;
esac

# ================= stage 6 reply, pasted verbatim =================
# Command: LOCAL_PORT=11435 bash opencsusm.sh 6
# Actual EC2 response through SSH, not a local inference response.
# {"id":"chatcmpl-978","object":"chat.completion","created":1791780659,"model":"qwen2.5:0.5b","system_fingerprint":"fp_ollama","choices":[{"index":0,"message":{"role":"assistant","content":"Hello John! It's nice to meet you. How can I assist you today?"},"finish_reason":"stop"}],"usage":{"prompt_tokens":32,"prompt_tokens_details":{"cached_tokens":0},"completion_tokens":18,"total_tokens":50}}
# ================= stage 8 output, pasted verbatim =================
# Command: bash opencsusm.sh 8
# Exit status: 0. STDOUT: 0 bytes. STDERR: 0 bytes.
# BEGIN VERBATIM STDOUT
# END VERBATIM STDOUT
# Instance stopped, then terminated; no project disks, groups, or keys remain.
# User-authorized Free-plan workaround: c7i-flex.large replaces c7i.2xlarge.
