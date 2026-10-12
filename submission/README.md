# OpenCSUSM45567 - CS 446 midterm

Status: **blocked at stage 2; not a completed midterm submission**.

## Choices

- Lane: `cpu`. Qwen2.5-0.5B needs no GPU to answer the greeting; the live G-instance quota is 0 vCPUs, while the Standard instance quota is 32 vCPUs.
- Exact PDF instance: `c7i.2xlarge`, 8 vCPUs and 16 GiB RAM, Ubuntu 24.04, `us-east-1`.
- Engine: Ollama only. No vLLM installation.
- Model: official `Qwen/Qwen2.5-0.5B-Instruct-GGUF`, Q4_K_M, 0.49B parameters, exposed through Ollama as `qwen2.5:0.5b`.
- Live AWS Linux compute price: **$0.357/hour**, checked before launch. EBS, IPv4, and applicable data transfer are additional charges; the compute price alone is not the total bill.
- Network: the script permits only TCP 22 from the laptop's current public IPv4 `/32`. Ollama is configured for `127.0.0.1:11434`. The client reaches it through an SSH tunnel, never a public inference port.
- Cost control: one instance, encrypted 20 GiB gp3 root disk with `DeleteOnTermination=true`, one-hour emergency shutdown, then mandatory stage 8 teardown. An emergency stop is not disk deletion.

## Actual execution on October 11, 2026 (America/Los_Angeles)

| Stage | Result | Evidence |
| --- | --- | --- |
| 1: quota and live price | Passed | `evidence/stage1.txt` |
| 2: launch | **Blocked by AWS Free plan** | `evidence/stage2-stderr.txt`; exit 254 |
| 3: install engine on EC2 | Not run; no instance launched | No cloud-install claim |
| 4: download/import model on EC2 | Not run; no instance launched | Hugging Face file downloaded and checksum-verified locally only |
| 5: SSH tunnel | Not run; no instance launched | No tunnel claim |
| 6: `I am John` greeting | **Not run** | No fabricated reply; no local reply substituted |
| 7: stop instance | Not applicable; none launched | Stage 2 failed before instance creation |
| 8: delete and verify | Passed after failed launch | Exit 0, zero-byte stdout and stderr; four empty resource lists |

The actual AWS launch error was:

```text
InvalidParameterCombination: The specified instance type is not eligible for Free Tier. For a list of Free Tier instance types, run 'describe-instance-types' with the filter 'free-tier-eligible=true'.
```

AWS's earlier dry-run permission check returned `DryRunOperation`; the actual launch still rejected the type. No project instance or EBS disk launched. The temporary project key pair and security group were deleted automatically after failure. Stage 8 was then run explicitly and independently verified against instances, volumes, security groups, and key pairs. All four resource lists are `[]`.

The user selected the exact PDF instance and instructed the run to stop if the Free plan blocks it. No instance substitution, paid-plan upgrade, AWS Organization, or Control Tower change was made. The Free plan remains the blocker. Completing stages 3-6 requires an account permitted to launch the exact instance, or instructor-approved permission to change the instance type.

## Downloaded model

The model was downloaded directly from the official Hugging Face repository, pinned to revision `9217f5db79a29953eb74d5343926648285ec7e67`. It is **491,400,032 bytes**. Its SHA-256 matches the publisher's LFS metadata:

```text
74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db
```

The weights are delivered separately from Git because of their size. `model-manifest.json` records the source, revision, byte count, and checksum. Stage 4 downloads and verifies the same official file on EC2 before importing it into Ollama.

## Resuming the exact assignment

Authenticate privately with AWS CLI (`aws login --profile opencsusm --region us-east-1`). No credentials or PEM files belong in Git. Use Git Bash on Windows, or Bash on Linux/macOS with AWS CLI, SSH, curl, and the normal GNU tools installed.

From this directory, run stages 1 and 2 only when the account is allowed to launch `c7i.2xlarge`. Then run stages 3 and 4; they connect to EC2 over SSH and execute there. Stage 5 prints the command for a second terminal. Leave that tunnel running and run stage 6 in the first terminal. Confirm the actual JSON assistant reply contains `John`. If local port 11434 is already occupied, export `LOCAL_PORT=11435` for both stages 5 and 6; the EC2 service port stays 11434.

Run stage 7 and then stage 8. Save the real stage 6 response and successful empty stage 8 output in the comment sections at the bottom of `opencsusm.sh`, replacing the current blocked-state record. Validate teardown even if installation or inference fails. Only then is the assignment ready to submit.

```bash
bash opencsusm.sh 1
bash opencsusm.sh 2
bash opencsusm.sh 3
bash opencsusm.sh 4
bash opencsusm.sh 5
# Execute the printed tunnel command in a second terminal; leave it running.
bash opencsusm.sh 6
bash opencsusm.sh 7
bash opencsusm.sh 8
```

`.opencsusm-state/` holds the temporary private key and local operational state. `submission/.gitignore` excludes it, private PEM files, model weights, and environment files. Stage 8 deletes its PEM file. `submission/.gitattributes` preserves Bash-compatible LF line endings on Windows. No private keys, AWS credentials, weights, or unrelated existing submission files were included in this task's commit.

The existing course fork is [Darthh/OpenCSUSM45567](https://github.com/Darthh/OpenCSUSM45567). Its canonical GitHub name was restored from OpenCSUSM55435 to the name selected by the user. No new fork was needed. **Canvas submission was not made because the required cloud greeting is incomplete.**

Sources: the supplied CS446_OpenCSUSM_Project.pdf and GitHubForkCommands.txt; actual AWS CLI output in `evidence/`; [official Qwen model card](https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF); [Ollama GGUF import](https://docs.ollama.com/import); [Ollama OpenAI compatibility](https://docs.ollama.com/api/openai-compatibility); [AWS Free Tier EC2 eligibility](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-free-tier-usage.html).
