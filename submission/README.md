# OpenCSUSM45567 - CS 446 midterm

**The John task passed on the user-authorized Free-plan workaround. All eight stages ran, and teardown was verified.**

The PDF names `c7i.2xlarge` for the CPU lane. AWS rejected that type on this account's Free plan. The user then authorized a Free-plan workaround, so the run used `c7i-flex.large` with the same engine, model, prompt, SSH-only access, and teardown. This instance substitution is a documented difference from the PDF; instructor acceptance of that difference has not been established. No Canvas submission was made.

## Choices and actual reply

- Lane: `cpu`, because a 0.5B greeting needs no GPU and the live G-instance quota was 0 vCPUs.
- Instance: one `c7i-flex.large`, 2 vCPUs, 4 GiB RAM, Ubuntu 24.04, `us-east-1`. Both the instance and Ubuntu image were verified Free Tier eligible.
- Engine: Ollama 0.40.3, running on CPU. No vLLM installation.
- Model: official Hugging Face `Qwen/Qwen2.5-0.5B-Instruct-GGUF`, Q4_K_M, imported as `qwen2.5:0.5b`.
- Live compute list price: $0.08479/hour, checked before launch. The Free plan uses remaining credits; EBS, public IPv4, and applicable data transfer are additional usage. Final billed usage can be delayed, so no exact final charge is claimed.

The actual user message was `I am John`, with `max_tokens=20` and `temperature=0`. The EC2 model replied:

> Hello John! It's nice to meet you. How can I assist you today?

The complete, unedited response JSON is in `evidence/stage6-reply.json` and pasted as a comment at the bottom of `opencsusm.sh`. It reports 18 completion tokens and a normal `stop` finish reason.

## Verified execution on October 11, 2026 (America/Los_Angeles)

| Stage | Result | Evidence |
| --- | --- | --- |
| 1: quota and live price | Passed: G quota 0, Standard quota 32, $0.08479/hour | `stage1.txt` |
| 2: launch | Passed: exactly one c7i-flex.large | `stage2-stdout.txt`, `run-status.json` |
| 3: install engine on EC2 | Passed: Ollama 0.40.3 | `stage3-stdout.txt` |
| 4: download/import model on EC2 | Passed: official weights, SHA-256 matches, alias imported | `stage4-stdout.txt`, `model-manifest.json` |
| 5: SSH tunnel | Passed: laptop 127.0.0.1:11435 to EC2 127.0.0.1:11434 | `stage5-tunnel-command.txt` |
| 6: John greeting | Passed: actual assistant reply contains John | `stage6-reply.json` |
| 7: stop instance | Passed: AWS state verified stopped | `stage7-stdout.txt`, `stage7-stderr.txt`, `run-status.json` |
| 8: delete and verify | Passed: exit 0; stdout and stderr both 0 bytes | `stage8-stdout.txt`, `stage8-stderr.txt`, four empty inventories |

All listed evidence files are under `submission/evidence/`. The instance's final AWS state is `terminated`; all project nonterminated-instance, volume, security-group, and key-pair inventories are `[]`. `account-plan-after-run.json` confirms **FREE / ACTIVE** after the run. The private key was deleted. No account upgrade, AWS Organization, or Control Tower change was made.

## Endpoint and cost controls

The security group had exactly one inbound rule: TCP 22 from the laptop's public IPv4 `/32`. No inference port or IPv6 ingress was opened. `network-verification.json` records the verified rule while omitting the owner's address. Ollama's actual listening socket was `127.0.0.1:11434`, captured in stage 4. The request used local port 11435 because the laptop's existing Ollama service occupies 11434; the remote model port remained 11434. The SSH tunnel closed when the instance stopped.

The root disk was encrypted 20 GiB gp3 with `DeleteOnTermination=true`. The script includes an emergency one-hour compute shutdown, automatic launch-failure cleanup, and explicit stage 8 disk/resource deletion. Stopping alone is not teardown.

## Model download and rerunning

The same model was downloaded locally and on EC2 from the official Hugging Face repository at revision `9217f5db79a29953eb74d5343926648285ec7e67`. The downloaded GGUF is 491,400,032 bytes, with verified SHA-256:

```text
74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db
```

Weights are delivered separately from Git. `model-manifest.json` records the source and verification. The earlier exact-instance quota/price check and actual AWS rejection are preserved as `exact-instance-stage1.txt` and `exact-instance-launch-error.txt`.

Use Git Bash on Windows, or Bash with AWS CLI, SSH, curl, and GNU tools. Authenticate privately with `aws login --profile opencsusm --region us-east-1`. From this directory:

```bash
export LOCAL_PORT=11435  # Use the same value for stages 5 and 6.
bash opencsusm.sh 1
bash opencsusm.sh 2
bash opencsusm.sh 3
bash opencsusm.sh 4
bash opencsusm.sh 5
# In a second terminal, execute the printed SSH tunnel command and leave it running.
bash opencsusm.sh 6
bash opencsusm.sh 7
bash opencsusm.sh 8
```

Stages 3/4 execute on EC2 through SSH. Stage 6 executes locally through the tunnel. Always run stage 8 after any failed install/test as well. `.opencsusm-state/`, private keys, weights, and environment files are ignored; `.gitattributes` preserves LF endings. This task's commit includes only task files and evidence, with no credentials or unrelated submission changes.

Repository: [Darthh/OpenCSUSM45567](https://github.com/Darthh/OpenCSUSM45567).

Sources: supplied CS446_OpenCSUSM_Project.pdf; actual AWS/SSH output in `evidence/`; [official Qwen model](https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF); [Ollama import](https://docs.ollama.com/import); [Ollama OpenAI compatibility](https://docs.ollama.com/api/openai-compatibility); [AWS Free Tier EC2 eligibility](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-free-tier-usage.html).
