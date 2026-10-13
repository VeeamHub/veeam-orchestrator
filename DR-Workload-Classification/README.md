# Veeam Recovery Orchestrator - DR Workload Classification (planning tool)

## Author

Klaus Wittenberg (@WittKlaus)

## Function

A single, offline HTML file for DR concept workshops. It prepares the input for Veeam Recovery
Orchestrator plans:

* Import an inventory: RVTools export, Veeam ONE report *VMs Configuration* (vSphere, Hyper-V) or a CSV list
* Rate each workload on business impact, regulatory requirements and data sensitivity and get a
  protection tier (Tier 0–4) with target RPO/RTO
* Capture dependencies and see weakest-link risks in a dependency network
* Derive runbook groups as candidates for orchestration plans, with start order and a foundation block
* Export a formatted Excel workbook for the hand-over

Source code, releases, example data and issues:
https://github.com/WittKlaus/dr-workload-classification

***NOTE:*** The tool produces a structured proposal, not a result. Before using it with a customer, I
strongly recommend you:

* Validate the classification with the system owners in a workshop
* Treat the default weights and thresholds as a starting point; the calibration belongs to the customer
* Read the README in the source repository

## Known Issues

The tool is in beta. Open issues are tracked in the source repository.

## Requirements

* A current browser (Edge, Chrome, Firefox). No installation, no server, no internet connection
* An inventory export (RVTools, Veeam ONE or CSV), or manual entry in the tool
* Veeam Recovery Orchestrator to implement the resulting plans

## Additional Information

`DR_Workload_Classification.html` in this folder is version v0.16.1-beta. The latest release is always
available at https://github.com/WittKlaus/dr-workload-classification/releases. Download the file, open it
in the browser and drop an inventory file on it.

To verify the file, compare its SHA-256 with `DR_Workload_Classification.html.sha256`:

```powershell
Get-FileHash .\DR_Workload_Classification.html -Algorithm SHA256
```

Customer data never leaves the browser: the file makes no network calls, has no telemetry and no AI
at runtime. Community project, not created by Veeam R&D, not validated by Veeam QA, not covered by
Veeam Support.
