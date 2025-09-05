# Generate Puppet Infrastructure
***Generate Puppet infrastructure including VMs, VPCs, Subnets, Security Groups, and more in AWS using Terraform IaC configuration***

> Note: *Current* Puppet Core | 8.14.0 (https://help.puppet.com/core/current/Content/PuppetCore/puppet_index.htm)

## Generate infrastructure using Terraform IaC
### 1. Create TF_VAR_ variable for the Puppet API KEY
Pass a variable in a more secure fashion from a session perspective ([See Note](#important-note-regarding-security-implications)).  Terraform will view this as the `puppet_api_key` variable, picking it up automatically.
```bash
$env:TF_VAR_puppet_api_key="your-real-api-key"
```
  > Eg:   `$env:TF_VAR_puppet_api_key="007d8ed95e50690547d1dfb5576718cc550524a60411bf80e8a10a0527f3f34e"`

To list the new variable just type `$env:TF_VAR_puppet_api_key` or to list all env vars type `Get-ChildItem env:`

### 2. Run `terraform init` then `terraform apply` to generate infrastructure
```bash
terraform init
terraform apply
```

### 3. Confirm EC2 instances created
Now is probably a good time to check EC2 Console to ensure instances were created, and that you can use AWS Instance Connect to open a terminal session for each.

## Review userdata in `main.tf`
The userdata for Puppet Core 8.x repo setup is a script that configures the Puppet repository on each instance. Here's a breakdown of what it does:

1. Sets the script's `API_KEY` variable to the automatically picked up `$TF_VAR_puppet_api_key` session environment variable.
2. Updates the apt package lists with `apt-get update` 
3. Installs dependencies (wget, gnupg)
4. Uses `wget --content-disposition` with the URL of the package to enable *based on OS and version*
   
   > **Eg**: https://apt-puppetcore.puppet.com/public/*puppet8-release-noble*.deb. Note that for Ubuntu releases, the version_code_name is the adjective, not the animal.

5. Use dpkg on the resource `dpkg -i puppet8...`
6. Overwrite contents of `/etc/apt/auth.conf.d/apt-puppetcore-puppet.conf` with login `forge-key`, and the value from the `API_KEY`variable.
   > **Note**: forge-key is a string literal. API_KEY is the Forge API key associated with your free or paid Puppet Core user.

   ```bash
   cat >/etc/apt/auth.conf.d/apt-puppetcore-puppet.conf <<EOC
   machine apt-puppetcore.puppet.com
   login forge-key
   password $API_KEY
   EOC
   ```
7. Sets permissions on the `apt-puppetcore-puppet.conf` config file.
   ```bash
   chmod 600 /etc/apt/auth.conf.d/apt-puppetcore-puppet.conf
   ```

8. Create outgoing success message  

[🔝Back to top](#generare-puppet-infrastructure)

---

## Important note regarding security implications

### TL;DR: 
If a `TF_VAR_` is used in a resource argument that Terraform tracks, it will be written to the **state file in plaintext JSON**, just like other input methods. The real difference between methods (`TF_VAR_`, `tfvars`, CLI flags) is more about **runtime exposure**, not whether the secret lands in state. No matter **how you pass the variable into Terraform** (`TF_VAR_*`, CLI flag, tfvars file, remote vars, etc.), if that variable’s value is used in a resource argument that Terraform tracks in state, it will **end up in the state file** unless the ***provider*** marks that attribute as **sensitive**.

---

### How it works:

* Terraform state contains **all arguments and computed values** needed to manage resources.

* For example:

  ```hcl
  resource "aws_db_instance" "db" {
    username = var.db_user
    password = var.db_password
  }
  ```

  Even if `db_password` came from `TF_VAR_db_password`, Terraform writes it into `terraform.tfstate` so it can reconcile drift.

* Some providers (AWS, GCP, Azure) declare attributes as `Sensitive`, so the **CLI output masks them**, but the raw **state file still contains the secret in plaintext JSON**.

---

### Implications:

* State files are the **highest risk point** for secrets, not the variable input method.
* Anyone with access to your backend storage (local disk, S3 bucket, Terraform Cloud, etc.) can read those secrets.
* Even with `sensitive = true` in variable definitions, that only prevents Terraform from showing them in plan/apply output — it does **not** remove them from state.
* **Input method security (TF_VAR_ vs tfvars vs CLI)** only affects *runtime exposure* (shell history, process list, CI/CD logs). **State exposure is the same either way.**

---

### Mitigations:

1. **Remote state with encryption & access controls**

   * S3 with KMS, GCS with CMEK, Azure Blob with SSE, etc.
   * Limit IAM permissions strictly.

2. **Terraform Cloud / Enterprise state**

   * Encrypted and access-controlled.

3. **Secret Managers instead of storing in state**

   * E.g., for AWS RDS passwords, generate them with `aws_secretsmanager_secret_version` instead of `aws_db_instance.password`.
   * This way, Terraform references the secret ARN, not the actual password value.

4. **Use `ignore_changes` lifecycle** where appropriate

   * Prevents Terraform from persisting values it shouldn’t manage.

[🔝Back to top](#generare-puppet-infrastructure)

---