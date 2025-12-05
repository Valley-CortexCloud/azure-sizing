# Cortex Cloud Sizing | Azure Assessment

![Platform](https://img.shields.io/badge/Platform-Azure-blue)
![Language](https://img.shields.io/badge/Language-Bash-green)
![Security](https://img.shields.io/badge/Security-Read--Only-success)

A zero-dependency, **read-only** assessment tool designed to right-size Cortex Cloud & XSIAM architectures. This script uses **Azure Resource Graph** to instantly scan your environment and calculate the required Credit consumption based on active workloads.

## 🚀 Quick Start (Cloud Shell)

You can run this tool directly in the **Azure Cloud Shell (Bash)**. No cloning or installation is required.

Copy and paste the following command:

```bash
bash <(curl -sL [https://raw.githubusercontent.com/Valley-CortexCloud/azure-sizing/main/azure-sizing.sh](https://raw.githubusercontent.com/Valley-CortexCloud/azure-sizing/main/azure-sizing.sh))
