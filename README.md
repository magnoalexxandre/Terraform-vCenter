# terraform-vcenter

Provisionamento declarativo de VMs no VMware vCenter usando **Terraform** e **Terragrunt**.

O modelo de operacao e simples: cada VM e um arquivo YAML individual. Criar, alterar ou remover uma VM e apenas criar, editar ou deletar o arquivo correspondente — sem tocar em HCL.

---

## Indice

1. [Arquitetura](#1-arquitetura)
2. [Pre-requisitos](#2-pre-requisitos)
3. [Estrutura do repositorio](#3-estrutura-do-repositorio)
4. [Configuracao inicial](#4-configuracao-inicial)
5. [Variaveis de ambiente](#5-variaveis-de-ambiente)
6. [Gerenciamento de VMs](#6-gerenciamento-de-vms)
7. [Referencia YAML — Linux](#7-referencia-yaml--linux)
8. [Referencia YAML — Windows](#8-referencia-yaml--windows)
9. [Comandos](#9-comandos)
10. [State e locking](#10-state-e-locking)
11. [Convencoes de nomenclatura](#11-convencoes-de-nomenclatura)
12. [Operacoes de risco](#12-operacoes-de-risco)
13. [Troubleshooting](#13-troubleshooting)

---

## 1. Arquitetura

```
Developer
    │
    │  terragrunt plan / apply
    ▼
Terragrunt (raiz)
    ├── Gera provider.tf  (vSphere)
    ├── Gera backend.tf   (MinIO S3-compatible)
    │
    ├── envs/des/linux/   ──► module/vm-linux  ──► vCenter DES
    ├── envs/des/windows/ ──► module/vm-windows ──► vCenter DES
    ├── envs/hom/linux/   ──► module/vm-linux  ──► vCenter HOM
    ├── envs/hom/windows/ ──► module/vm-windows ──► vCenter HOM
    ├── envs/prod/linux/  ──► module/vm-linux  ──► vCenter PROD
    └── envs/prod/windows/──► module/vm-windows ──► vCenter PROD
                                                        │
                                              State + Lock
                                                        │
                                                     MinIO
                                          (terraform-vcenter-state)
```

### State e locking

O state e o lock ficam no **MinIO on-prem** (S3-compatible). O Terraform 1.10+
usa `use_lockfile = true` para gerar um arquivo `.tflock` no mesmo bucket durante
o `apply`, eliminando a necessidade de DynamoDB ou qualquer servico externo.

```
terraform-vcenter-state/          (bucket MinIO)
├── envs/des/linux/
│   ├── terraform.tfstate
│   └── terraform.tfstate.tflock  (temporario, durante apply)
├── envs/des/windows/
│   └── ...
├── envs/hom/linux/
│   └── ...
└── envs/prod/windows/
    └── ...
```

---

## 2. Pre-requisitos

### Ferramentas

| Ferramenta | Versao minima | Motivo |
|---|---|---|
| Terraform | >= 1.10 | `use_lockfile` nativo |
| Terragrunt | >= 0.55 | `fileset()` + `yamldecode()` no locals |
| mc (MinIO Client) | qualquer | Setup inicial do bucket |

```bash
# Terraform
wget https://releases.hashicorp.com/terraform/1.10.5/terraform_1.10.5_linux_amd64.zip
unzip terraform_1.10.5_linux_amd64.zip && sudo mv terraform /usr/local/bin/

# Terragrunt
curl -sL https://github.com/gruntwork-io/terragrunt/releases/download/v0.55.1/terragrunt_linux_amd64 \
  -o /usr/local/bin/terragrunt && chmod +x /usr/local/bin/terragrunt

# mc CLI
curl -sL https://dl.min.io/client/mc/release/linux-amd64/mc \
  -o /usr/local/bin/mc && chmod +x /usr/local/bin/mc
```

### Acessos necessarios

| Recurso | Permissoes |
|---|---|
| MinIO | Admin (setup inicial do bucket) |
| vCenter | `VirtualMachine.*`, `Datastore.AllocateSpace`, `Network.Assign`, `Resource.AssignVMToPool`, `Folder.Create` |

### Templates vCenter

Os modulos clonam a partir de templates pre-existentes no vCenter. Os nomes
esperados por ambiente sao configurados nos `terragrunt.hcl` de cada stack:

| Ambiente | Linux | Windows |
|---|---|---|
| des | `TEMPLATE-LINUX-DES` | `TEMPLATE-WINDOWS-DES` |
| hom | `TEMPLATE-LINUX-HOM` | `TEMPLATE-WINDOWS-HOM` |
| prod | `TEMPLATE-LINUX-PROD` | `TEMPLATE-WINDOWS-PROD` |

Os templates devem ter VMware Tools instalado. Linux requer tambem Perl para
guest customization (hostname, IP, DNS).

---

## 3. Estrutura do repositorio

```
terraform-vcenter/
├── terragrunt.hcl               # Config raiz: provider vSphere + backend MinIO
│
├── modules/
│   ├── vm-linux/                # Modulo reutilizavel — VMs Linux
│   │   ├── versions.tf          # Terraform >= 1.10, vsphere ~> 2.6
│   │   ├── provider-vars.tf     # vsphere_server, vsphere_user, vsphere_password
│   │   ├── variables.tf         # Variaveis de entrada (datacenter, cluster, vms...)
│   │   ├── main.tf              # Local: resolucao de datastores
│   │   ├── vsphere.data.tf      # Data sources (datacenter, template, redes, pools)
│   │   ├── vsphere.virtual-machine.tf  # Resource vsphere_virtual_machine (for_each)
│   │   └── outputs.tf           # Output: name, ip, uuid, id por VM
│   │
│   └── vm-windows/              # Modulo reutilizavel — VMs Windows (mesma estrutura)
│       └── ...
│
└── envs/
    ├── des/                     # Ambiente de Desenvolvimento
    │   ├── env.hcl              # datacenter, cluster, datastore do ambiente
    │   ├── linux/
    │   │   ├── terragrunt.hcl   # Descobre YAMLs automaticamente
    │   │   └── vms/             # 1 arquivo YAML = 1 VM
    │   │       ├── app01.yaml
    │   │       ├── app02.yaml
    │   │       └── db01.yaml
    │   └── windows/
    │       ├── terragrunt.hcl
    │       └── vms/
    │           └── web01.yaml
    │
    ├── hom/                     # Ambiente de Homologacao
    │   ├── env.hcl
    │   ├── linux/terragrunt.hcl + vms/
    │   └── windows/terragrunt.hcl + vms/
    │
    └── prod/                    # Ambiente de Producao
        ├── env.hcl
        ├── linux/terragrunt.hcl + vms/
        └── windows/terragrunt.hcl + vms/
```

### Como o Terragrunt descobre as VMs

O `terragrunt.hcl` de cada stack usa `fileset()` para encontrar todos os YAMLs
na pasta `vms/` e os converte automaticamente em um mapa Terraform:

```hcl
locals {
  vm_files = fileset("${get_terragrunt_dir()}/vms", "*.yaml")
  vms = {
    for f in local.vm_files :
    trimsuffix(f, ".yaml") => yamldecode(file("${get_terragrunt_dir()}/vms/${f}"))
  }
}
```

`app01.yaml` + `app02.yaml` + `db01.yaml` viram:

```hcl
vms = {
  "app01" = { vm_name = "DES-LNX-APP01", cpus = 2, ... }
  "app02" = { vm_name = "DES-LNX-APP02", cpus = 4, ... }
  "db01"  = { vm_name = "DES-LNX-DB01",  cpus = 8, ... }
}
```

O nome do arquivo YAML e a key no Terraform e no state. Nao renomeie arquivos
sem usar `terraform state mv` antes (ver [Operacoes de risco](#12-operacoes-de-risco)).

---

## 4. Configuracao inicial

### 4.1 Criar o bucket MinIO

```bash
# Configurar alias
mc alias set minio https://minio-des.meudominio.com ACCESS_KEY SECRET_KEY

# Criar bucket
mc mb minio/terraform-vcenter-state

# Habilitar versionamento (protege contra corrupcao do state)
mc version enable minio/terraform-vcenter-state
```

### 4.2 Criar service account no MinIO

```bash
mc admin user add minio svc-terraform SenhaForte123!

cat > /tmp/tf-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["s3:GetObject","s3:PutObject","s3:DeleteObject","s3:ListBucket","s3:GetBucketVersioning"],
    "Resource": ["arn:aws:s3:::terraform-vcenter-state","arn:aws:s3:::terraform-vcenter-state/*"]
  }]
}
EOF

mc admin policy create minio terraform-state /tmp/tf-policy.json
mc admin policy attach minio terraform-state --user svc-terraform
```

### 4.3 Ajustar env.hcl de cada ambiente

Substituir os placeholders pelos nomes reais do seu vCenter:

```hcl
# envs/des/env.hcl
locals {
  environment       = "des"
  datacenter        = "DC-SEU-DATACENTER"
  cluster           = "CLUSTER-DES"
  datastore_default = "DS-DES-SSD-01"
}
```

### 4.4 Ajustar template_name

Em cada `envs/{env}/{os}/terragrunt.hcl`, definir o nome exato do template
que existe no vCenter para aquele ambiente e OS.

```bash
# Descobrir nomes de templates no vCenter via govc
export GOVC_URL="vcenter.meudominio.com"
export GOVC_USERNAME="svc-terraform@vsphere.local"
export GOVC_PASSWORD="senha"
export GOVC_INSECURE=true

govc ls /SEU-DC/vm/          # lista VMs e templates
govc ls /SEU-DC/datastore/   # lista datastores
govc ls /SEU-DC/network/     # lista portgroups
govc find . -type p          # lista resource pools
```

---

## 5. Variaveis de ambiente

Todas as credenciais sao passadas exclusivamente via variaveis de ambiente.
Nada e hardcoded no repositorio.

| Variavel | Descricao |
|---|---|
| `VSPHERE_SERVER` | Endereco do vCenter (ex: `vcenter.meudominio.com`) |
| `VSPHERE_USER` | Usuario vSphere (ex: `svc-terraform@vsphere.local`) |
| `VSPHERE_PASSWORD` | Senha do usuario vSphere |
| `MINIO_ENDPOINT` | URL do MinIO (ex: `https://minio-des.meudominio.com`) |
| `MINIO_ACCESS_KEY` | Access key do MinIO |
| `MINIO_SECRET_KEY` | Secret key do MinIO |

Exemplo de configuracao:

```bash
export VSPHERE_SERVER="vcenter.meudominio.com"
export VSPHERE_USER="svc-terraform@vsphere.local"
export VSPHERE_PASSWORD="sua-senha"
export MINIO_ENDPOINT="https://minio-des.meudominio.com"
export MINIO_ACCESS_KEY="svc-terraform"
export MINIO_SECRET_KEY="sua-senha-minio"
```

---

## 6. Gerenciamento de VMs

### Criar uma VM

Crie um arquivo YAML em `envs/{env}/{os}/vms/{nome}.yaml`. O nome do arquivo
sera a key no Terraform.

```bash
# Criar VM Linux em DES
cat > envs/des/linux/vms/app03.yaml << 'EOF'
vm_name: DES-LNX-APP03
cpus: 2
memory_mb: 4096
disk_size_gb: 50
portgroup: VLAN-DES-100
ip_address: "10.0.1.12"
netmask: 24
gateway: "10.0.1.1"
dns_servers:
  - "10.0.0.10"
resource_pool: CLUSTER-DES/Resources
folder: DES/Linux
EOF

cd envs/des/linux
terragrunt plan   # verificar: "+ vsphere_virtual_machine.this["app03"]"
terragrunt apply
```

### Alterar uma VM

Edite o YAML e aplique:

```bash
# Aumentar recursos da app01
vim envs/des/linux/vms/app01.yaml
# cpus: 2 → 4
# memory_mb: 4096 → 8192

cd envs/des/linux
terragrunt plan   # mostra somente a alteracao na app01
terragrunt apply  # hot-add, sem reboot
```

### Remover uma VM

```bash
# ATENCAO: a VM sera destruida no vCenter
rm envs/des/linux/vms/app03.yaml

cd envs/des/linux
terragrunt plan   # verificar: "- vsphere_virtual_machine.this["app03"]"
# Confirmar que e a VM correta antes de aplicar
terragrunt apply
```

---

## 7. Referencia YAML — Linux

### Campos obrigatorios

```yaml
vm_name: DES-LNX-APP01       # Nome da VM no vCenter (convertido para UPPERCASE)
cpus: 2                      # Numero de vCPUs
memory_mb: 4096              # Memoria em MB
disk_size_gb: 50             # Tamanho do disco do SO em GB
portgroup: VLAN-DES-100      # Nome do portgroup/VLAN no vCenter
ip_address: "10.0.1.10"      # IP estatico
netmask: 24                  # Mascara CIDR (ex: 24 = /24 = 255.255.255.0)
gateway: "10.0.1.1"          # Gateway padrao
dns_servers:                 # Servidores DNS (lista)
  - "10.0.0.10"
  - "10.0.0.11"
resource_pool: CLUSTER-DES/Resources  # Resource pool no vCenter
folder: DES/Linux            # Pasta no vCenter (usar "/" para subpastas)
```

### Campos opcionais

```yaml
annotation: "Servidor de aplicacao"  # Nota no vCenter (IP adicionado automaticamente)
datastore: "DS-SSD-ESPECIFICO"       # Datastore especifico (padrao: env.hcl)
cpu_hot_add_enabled: true            # Aumentar CPU sem reboot (padrao: true)
memory_hot_add_enabled: true         # Aumentar RAM sem reboot (padrao: true)
extra_disks:                         # Discos adicionais
  - label: data                      # Label do disco (obrigatorio)
    size_gb: 500                     # Tamanho em GB (obrigatorio)
    thin_provisioned: true           # Thin provisioning (padrao: true)
    unit_number: 1                   # SCSI unit number (opcional, auto se omitido)
tags:                                # Tags customizadas (mapa)
  ambiente: des
  time: plataforma
```

### Exemplo completo — VM de banco de dados

```yaml
vm_name: DES-LNX-DB01
annotation: PostgreSQL 16
cpus: 8
memory_mb: 32768
disk_size_gb: 100
portgroup: VLAN-DES-DB-200
ip_address: "10.0.2.10"
netmask: 24
gateway: "10.0.2.1"
dns_servers:
  - "10.0.0.10"
  - "10.0.0.11"
resource_pool: CLUSTER-DES/Resources
folder: DES/Linux/Database
extra_disks:
  - label: pgdata
    size_gb: 500
```

---

## 8. Referencia YAML — Windows

### Campos obrigatorios (alem dos comuns)

```yaml
vm_name: DES-WIN-WEB01       # Nome da VM no vCenter (convertido para UPPERCASE)
cpus: 4
memory_mb: 8192
disk_size_gb: 100
portgroup: VLAN-DES-100
ip_address: "10.0.1.20"
netmask: 24
gateway: "10.0.1.1"
dns_servers:
  - "10.0.0.10"
resource_pool: CLUSTER-DES/Resources
folder: DES/Windows
admin_password: SenhaForte!2026   # OBRIGATORIO — senha do Administrator local
```

> **Seguranca:** `admin_password` e tratado como `sensitive = true` no modulo.
> Evite commitar senhas reais em texto claro. Considere usar um secret manager
> ou variavel de ambiente para injetar o valor.

### Campos opcionais exclusivos do Windows

```yaml
full_name: "Administrator"          # Nome completo (Sysprep) — padrao: Administrator
organization_name: "MagnUX"         # Organizacao (Sysprep) — padrao: MagnUX
product_key: ""                     # Chave de produto Windows — padrao: vazio
workgroup: "WORKGROUP"              # Workgroup — padrao: WORKGROUP
time_zone: 65                       # Timezone Windows — padrao: 65 (E. South America)
```

### Exemplo completo — VM Windows

```yaml
vm_name: DES-WIN-WEB01
cpus: 4
memory_mb: 8192
disk_size_gb: 100
portgroup: VLAN-DES-100
ip_address: "10.0.1.20"
netmask: 24
gateway: "10.0.1.1"
dns_servers:
  - "10.0.0.10"
  - "10.0.0.11"
resource_pool: CLUSTER-DES/Resources
folder: DES/Windows
admin_password: SenhaForte!2026
organization_name: "Minha Empresa"
time_zone: 65
```

---

## 9. Comandos

### Fluxo basico

```bash
# 1. Exportar variaveis de ambiente (ver secao 5)

# 2. Inicializar (necessario na primeira vez ou apos git clone)
cd envs/des/linux
terragrunt init

# 3. Verificar o que sera feito
terragrunt plan

# 4. Aplicar
terragrunt apply
```

### Operacoes por escopo

```bash
# Stack especifico
cd envs/des/linux
terragrunt plan
terragrunt apply

# Todos os stacks de um ambiente
cd envs/des
terragrunt run-all plan
terragrunt run-all apply

# Todos os ambientes
cd envs
terragrunt run-all plan
terragrunt run-all apply
```

### Inspecionar o state

```bash
cd envs/des/linux

# Listar todos os recursos gerenciados
terragrunt state list

# Detalhes de uma VM especifica
terragrunt state show 'vsphere_virtual_machine.this["app01"]'
```

### Destruir recursos

```bash
# Destruir uma VM especifica (sem remover o YAML)
terragrunt destroy -target='vsphere_virtual_machine.this["app01"]'

# Destruir todo o stack (CUIDADO: remove todas as VMs do stack)
terragrunt destroy
```

### Importar VM existente

```bash
# 1. Criar o YAML com os dados da VM existente
# 2. Importar pelo caminho no vCenter
terragrunt import \
  'vsphere_virtual_machine.this["app01"]' \
  '/DC-MAGNUX/vm/DES/Linux/DES-LNX-APP01'

# 3. Verificar drift
terragrunt plan
# Ajustar o YAML ate o plan mostrar 0 changes
```

---

## 10. State e locking

### Localizacao dos arquivos

| Arquivo | Caminho no MinIO | Descricao |
|---|---|---|
| State | `envs/{env}/{os}/terraform.tfstate` | Estado atual da infra |
| Lock | `envs/{env}/{os}/terraform.tfstate.tflock` | Existe apenas durante apply |

### Desbloquear state preso

Se um `apply` falhar no meio e o `.tflock` nao for removido automaticamente:

```bash
# O LOCK_ID aparece na mensagem de erro:
# "Error locking state: Lock Info: ID: xxxxxxxx-xxxx-..."
terragrunt force-unlock LOCK_ID
```

### Flags S3 para MinIO

O backend esta configurado com as flags necessarias para compatibilidade com MinIO:

```hcl
use_path_style              = true   # MinIO usa path-style (nao virtual-hosted)
skip_credentials_validation = true   # Nao valida contra AWS
skip_metadata_api_check     = true   # Nao chama metadata API da AWS
skip_requesting_account_id  = true   # Nao busca account ID da AWS
skip_s3_checksum            = true   # Evita erros de checksum
use_lockfile                = true   # Lock via .tflock no bucket
```

---

## 11. Convencoes de nomenclatura

| Elemento | Convencao | Exemplo |
|---|---|---|
| Arquivos `.tf` | dot-separated por recurso | `vsphere.data.tf`, `vsphere.virtual-machine.tf` |
| Recursos singleton | `"this"` como nome local | `data.vsphere_datacenter.this` |
| Recursos multiplos | indexado pela key do mapa | `vsphere_virtual_machine.this["app01"]` |
| Nome VM no vCenter | UPPERCASE | `DES-LNX-APP01` |
| Hostname Linux | lowercase | `des-lnx-app01` |
| Nome VM Windows | UPPERCASE, max 15 chars (NetBIOS) | `DES-WIN-WEB01` |
| Key no state | nome do arquivo YAML sem extensao | `app01.yaml` → `app01` |
| Portgroups | `VLAN-{ENV}-{NUMERO}` | `VLAN-DES-100`, `VLAN-DES-DB-200` |
| Folders | `{ENV}/{OS}[/SubPath]` | `DES/Linux`, `DES/Linux/Database` |
| Resource pools | `{CLUSTER}/Resources` | `CLUSTER-DES/Resources` |
| State keys | path relativo do stack | `envs/des/linux/terraform.tfstate` |

---

## 12. Operacoes de risco

### Tabela de impacto

| Operacao | Comportamento | Risco |
|---|---|---|
| Aumentar `cpus` | Hot-add, sem reboot | Baixo |
| Aumentar `memory_mb` | Hot-add, sem reboot | Baixo |
| Aumentar `disk_size_gb` | Expand no vCenter (resize no SO manual) | Baixo |
| Adicionar `extra_disks` | Disco novo adicionado (mount no SO manual) | Baixo |
| Trocar `portgroup` | Reconecta a NIC (breve perda de rede) | Medio |
| Alterar `vm_name` | Renomeia no vCenter, hostname interno NAO muda | Medio |
| Reduzir `cpus` ou `memory_mb` | Requer reboot da VM | Reboot |
| Reduzir `disk_size_gb` | **Impossivel** — vSphere nao suporta shrink | Bloqueado |
| Remover entry do YAML | **VM destruida no vCenter** | CRITICO |
| Renomear arquivo YAML | Terraform ve como destroy + create | CRITICO |

### Renomear a key do mapa sem destruir a VM

Se precisar renomear o arquivo YAML (e portanto a key no state), use `state mv`
**antes** de renomear o arquivo:

```bash
cd envs/des/linux

# 1. Mover no state primeiro
terragrunt state mv \
  'vsphere_virtual_machine.this["app01"]' \
  'vsphere_virtual_machine.this["webserver01"]'

# 2. Renomear o arquivo
mv vms/app01.yaml vms/webserver01.yaml

# 3. Plan deve mostrar 0 changes
terragrunt plan
```

### Remover VM do Terraform sem destruir no vCenter

```bash
cd envs/des/linux

# Remove do state (VM continua no vCenter)
terragrunt state rm 'vsphere_virtual_machine.this["app01"]'

# Remover o arquivo YAML
rm vms/app01.yaml

# Plan: 0 changes
terragrunt plan
```

### Regra de ouro

**Sempre leia o plan antes de aplicar.** Qualquer `destroy` ou `replace`
inesperado deve ser investigado antes de prosseguir.

```
Plan: X to add, Y to change, Z to destroy.
      ──────   ────────────  ─────────────
      Baixo       Medio          CRITICO
```

---

## 13. Troubleshooting

### State lock preso

```
Error locking state: Lock Info:
  ID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

```bash
terragrunt force-unlock xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

### MinIO inacessivel

```bash
# Checar conectividade
curl -s https://minio-des.meudominio.com/minio/health/live

# Checar credenciais
mc alias set test https://minio-des.meudominio.com $MINIO_ACCESS_KEY $MINIO_SECRET_KEY
mc ls test/terraform-vcenter-state
```

Causas comuns:
- Variaveis de ambiente nao exportadas
- Certificado CA interno nao esta no trust store do sistema
- URL sem schema (`https://`) no `MINIO_ENDPOINT`

### Template nao encontrado

```
Error: could not find template "TEMPLATE-LINUX-DES"
```

```bash
# Listar templates disponiveis
govc find /SEU-DC -type m | grep -i template

# Verificar nome exato (case-sensitive)
govc vm.info /SEU-DC/vm/TEMPLATE-LINUX-DES
```

Ajuste o campo `template_name` no `envs/{env}/{os}/terragrunt.hcl`.

### VM criada sem IP / sem customizacao de rede

A guest customization depende do VMware Tools instalado no template.

Verificar no template:
- **Linux:** `open-vm-tools` e `perl` instalados
- **Windows:** `VMware Tools` instalado e servico ativo

### Erro de certificado SSL

O provider vSphere esta configurado com `allow_unverified_ssl = true`
no `terragrunt.hcl` raiz, o que ignora erros de certificado. Adequado para
ambientes internos com CA propria; remover para producao com certificado valido.

### Provider nao inicializado

```bash
cd envs/des/linux
terragrunt init --reconfigure
```

Use `--reconfigure` quando o backend mudar (ex: novo bucket ou endpoint).
