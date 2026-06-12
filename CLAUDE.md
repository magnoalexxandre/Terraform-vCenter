# terraform-vcenter

Provisionamento declarativo de VMs no vCenter usando Terraform + Terragrunt.

## Estrutura

```
modules/
  vm-linux/           # Modulo reutilizavel VMs Linux
  vm-windows/         # Modulo reutilizavel VMs Windows
envs/
  {des,hom,prod}/
    env.hcl           # Variaveis do ambiente (datacenter, cluster, datastore)
    linux/
      terragrunt.hcl  # Config (le YAMLs de vms/ automaticamente)
      vms/*.yaml      # 1 arquivo YAML = 1 VM
    windows/
      terragrunt.hcl
      vms/*.yaml
```

## VMs

Cada VM e um arquivo YAML individual em `envs/{env}/{os}/vms/{nome}.yaml`.
O nome do arquivo = key no Terraform.

## State management

- Remote backend: MinIO (S3-compatible, on-prem)
- State locking: `use_lockfile = true` (arquivo .tflock no MinIO)
- Key pattern: `envs/{env}/{os}/terraform.tfstate`

## Comandos

```bash
cd envs/des/linux && terragrunt plan
cd envs/des/linux && terragrunt apply
terragrunt run-all plan --terragrunt-working-dir envs/
```

## Variaveis de ambiente

- `VSPHERE_SERVER` / `VSPHERE_USER` / `VSPHERE_PASSWORD`
- `MINIO_ENDPOINT` / `MINIO_ACCESS_KEY` / `MINIO_SECRET_KEY`

## Versionamento

Codigo versionado no Azure DevOps (somente controle de versao, sem CI/CD).
