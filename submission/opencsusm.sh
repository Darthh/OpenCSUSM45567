#!/usr/bin/env bash
# OpenCSUSM55435 — CS 446 midterm: your own OpenAI on one EC2 instance, over an SSH tunnel.
# Usage: bash opencsusm.sh <1-8>     (stages 3 and 4 run ON the instance, over ssh)
set -euo pipefail
export MSYS_NO_PATHCONV=1   # Git Bash on Windows: don't rewrite /aws/... into C:/Program Files/Git/aws/...
export AWS_PAGER=""

# ---------------- choices ----------------
# Lane: cpu — c7i.2xlarge + Ollama at $0.3570/hr (~280 h on $100), and it needs no G-quota request,
#             which starts at 0 and takes hours to days to approve. The test is identical either way.
LANE=cpu
TYPE=c7i.2xlarge
PORT=11434
# Model: smallest that passes. Ollama's qwen2.5:0.5b = Hugging Face Qwen/Qwen2.5-0.5B-Instruct, Q4_K_M, 398 MB.
MODEL=qwen2.5:0.5b
REGION=us-east-1
NAME=opencsusm              # tags the instance/volume, names the security group and key pair
KEYNAME=opencsusm
KEY=~/.ssh/$KEYNAME.pem

aws()    { command aws --region "$REGION" "$@"; }
iid()    { aws ec2 describe-instances --filters "Name=tag:Name,Values=$NAME" \
             "Name=instance-state-name,Values=pending,running,stopping,stopped" \
             --query 'Reservations[].Instances[].InstanceId' --output text; }
dns()    { aws ec2 describe-instances --filters "Name=tag:Name,Values=$NAME" "Name=instance-state-name,Values=running" \
             --query 'Reservations[0].Instances[0].PublicDnsName' --output text; }
on_box() { ssh -i "$KEY" -o StrictHostKeyChecking=accept-new "ubuntu@$(dns)" "$@"; }

case "${1:-}" in
1)  # quota + live price.  DO THIS ON DAY ONE.
    echo "lane=$LANE type=$TYPE model=$MODEL"
    # L-DB2E81BA = G and VT (gpu lane), L-1216C47A = Standard A,C,D,H,I,M,R,T,Z (cpu lane; c7i.2xlarge needs 8)
    for q in L-DB2E81BA L-1216C47A; do
        aws service-quotas get-service-quota --service-code ec2 --quota-code $q \
            --query '{quota:Quota.QuotaName,value:Quota.Value}' --output table
    done
    aws pricing get-products --service-code AmazonEC2 --filters \
        "Type=TERM_MATCH,Field=instanceType,Value=$TYPE" \
        "Type=TERM_MATCH,Field=location,Value=US East (N. Virginia)" \
        "Type=TERM_MATCH,Field=operatingSystem,Value=Linux" \
        "Type=TERM_MATCH,Field=tenancy,Value=Shared" \
        "Type=TERM_MATCH,Field=preInstalledSw,Value=NA" \
        "Type=TERM_MATCH,Field=capacitystatus,Value=Used" \
        --query 'PriceList' --output text | grep -o '\$[0-9.]* per On Demand [^"]*' | sort -u
    ;;
2)  # launch. Prints the ssh line. The meter starts here.
    if [ ! -f "$KEY" ]; then
        mkdir -p ~/.ssh
        aws ec2 create-key-pair --key-name $KEYNAME --query KeyMaterial --output text > "$KEY"
        chmod 400 "$KEY"
    fi
    MYIP=$(curl -fsS https://checkip.amazonaws.com)
    SG=$(aws ec2 create-security-group --group-name $NAME --description "OpenCSUSM: ssh from one address only" \
        --query GroupId --output text)
    # Port 22 from MY address only. The inference port is never opened — it rides the tunnel.
    aws ec2 authorize-security-group-ingress --group-id "$SG" --protocol tcp --port 22 --cidr "$MYIP/32" > /dev/null
    AMI=$(aws ssm get-parameter --query Parameter.Value --output text \
        --name /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id)
    ID=$(aws ec2 run-instances --image-id "$AMI" --instance-type $TYPE --key-name $KEYNAME --security-group-ids "$SG" \
        --block-device-mappings 'DeviceName=/dev/sda1,Ebs={VolumeSize=20,VolumeType=gp3,DeleteOnTermination=true}' \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$NAME}]" \
                             "ResourceType=volume,Tags=[{Key=Name,Value=$NAME}]" \
        --query 'Instances[0].InstanceId' --output text)
    aws ec2 wait instance-running --instance-ids "$ID"
    echo "ssh -i $KEY ubuntu@$(dns)"
    ;;
3)  # ssh in; install Ollama. It installs as a systemd service and is listening on 127.0.0.1:11434 when done.
    on_box 'curl -fsSL https://ollama.com/install.sh | sh'
    ;;
4)  # ssh in; pull the model and confirm the server is up (Ollama has no serve command to run).
    on_box "ollama pull $MODEL && ollama list && curl -sS localhost:$PORT"
    ;;
5)  # prints the tunnel command for a SECOND terminal. Leave it running.
    echo "ssh -i $KEY -N -L $PORT:localhost:$PORT ubuntu@$(dns)"
    ;;
6)  # the one test. 'localhost' is YOUR laptop; the request travels inside the ssh tunnel on port 22.
    curl -sS localhost:$PORT/v1/chat/completions \
        -H 'Content-Type: application/json' \
        -d '{"model": "'"$MODEL"'",
             "messages": [{"role": "user", "content": "I am John"}],
             "max_tokens": 20, "temperature": 0}'
    echo
    ;;
7)  # STOP — compute stops, the disk keeps costing.
    ID=$(iid)
    aws ec2 stop-instances --instance-ids $ID > /dev/null
    aws ec2 wait instance-stopped --instance-ids $ID
    ;;
8)  # DELETE — instance, disk, security group, key pair. Paste the (empty) output below as proof.
    ID=$(iid)
    if [ -n "$ID" ]; then
        aws ec2 terminate-instances --instance-ids $ID > /dev/null
        aws ec2 wait instance-terminated --instance-ids $ID
    fi
    aws ec2 delete-security-group --group-name $NAME 2> /dev/null || true
    aws ec2 delete-key-pair --key-name $KEYNAME > /dev/null
    rm -f "$KEY"
    # Proof: each of these prints nothing when everything is gone.
    iid
    aws ec2 describe-volumes --filters "Name=tag:Name,Values=$NAME" "Name=status,Values=creating,available,in-use" \
        --query 'Volumes[].VolumeId' --output text
    aws ec2 describe-security-groups --filters "Name=group-name,Values=$NAME" --query 'SecurityGroups[].GroupId' --output text
    aws ec2 describe-key-pairs --filters "Name=key-name,Values=$KEYNAME" --query 'KeyPairs[].KeyName' --output text
    ;;
*)  echo "usage: bash $0 <1-8>"; exit 1 ;;
esac
exit 0

# ================= stage 6 reply (bash opencsusm.sh 6), pasted verbatim =================
# TODO: paste here

# ================= stage 8 output (bash opencsusm.sh 8), pasted verbatim =================
# TODO: paste here — it should be empty
