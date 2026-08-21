# Terraform basics

`[101]` · written to be read cold, no project knowledge assumed

## The problem it solves

Setting up infrastructure by hand — clicking through a console, running commands on a
server — works once. Then you cannot answer basic questions about it. What exactly did
I create? Is the staging environment the same as production? If this machine dies, can
I rebuild it?

Terraform makes infrastructure a text file you keep in version control. The file
describes what should exist. Terraform's job is to make reality match it.

## You describe the end state, not the steps

This is the part that feels backwards at first. You do not write "create a server, then
attach a disk, then configure the network". You write what should exist when it is
finished:

```hcl
resource "aws_instance" "web" {
  ami           = "ami-0abc123"
  instance_type = "t3.micro"
  tags = {
    Name = "web-server"
  }
}
```

Terraform works out what to do. If nothing exists, it creates it. If it already exists
and matches, it does nothing. If someone changed the instance type by hand, it changes
it back.

That last behaviour is the point: the file is the truth, and reality is expected to
follow it.

## The pieces

**A resource** is one thing you want to exist — a server, a disk, a DNS record, a
firewall rule.

**A provider** is the plugin that knows how to talk to a particular platform. There is
an AWS provider, a Google Cloud provider, a Proxmox provider, and hundreds more. You
declare which ones you use and Terraform downloads them.

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

**Variables** are inputs, so the same configuration can be used with different values:

```hcl
variable "instance_type" {
  description = "Size of the server."
  type        = string
  default     = "t3.micro"
}
```

**Outputs** are values you want back out afterwards — an IP address, a generated name:

```hcl
output "server_ip" {
  value = aws_instance.web.public_ip
}
```

## The loop

Three commands, in this order:

```bash
terraform init     # download the providers — once per project, and after adding one
terraform plan     # show me what you would change
terraform apply    # do it
```

**`plan` is the important one.** It compares what you wrote against what exists and
prints the difference:

```
Plan: 1 to add, 0 to change, 0 to destroy.
```

Nothing happens during a plan. It is safe to run any time, and reading it before every
apply is the habit worth building — it is the only moment you get to notice that a
change you thought was small proposes destroying something.

## State — the piece that is easy to miss

Terraform keeps a file, `terraform.tfstate`, recording what it created. This is how it
connects "the resource named `web` in my config" to "the actual server with ID
`i-0abc123` at the provider".

Two consequences worth knowing on day one:

- **State is not optional.** Delete it and Terraform forgets it created anything. Run
  `apply` after that and it will happily build a second copy of everything.
- **State contains real values**, including passwords and keys that resources returned.
  It is not encrypted. Never commit it to Git — every `.gitignore` for a Terraform
  project excludes `*.tfstate`.

By default the file sits on your machine. Teams put it in shared remote storage
instead, so several people are not each keeping their own idea of what exists.

## Running it twice is safe

`apply` on an unchanged configuration does nothing and reports no changes. This is
called being *idempotent*, and it is what makes the tool trustworthy: you can run it to
check that reality still matches, not only to change things.

A plan that reports no changes is a real statement — it means nobody has edited
anything by hand behind your back.

## The rule that surprises people

Some edits update a resource in place. Others cannot be done to a live resource, so
Terraform **destroys and recreates** it. Renaming a thing, or changing a property fixed
at creation time, usually means replacement.

The plan always says which:

```
  # aws_instance.web must be replaced
Plan: 1 to add, 0 to change, 1 to destroy.
```

`1 to destroy` on what felt like a small edit is normal and not a bug — but it is
exactly why you read the plan before applying, rather than after.

## Terraform and OpenTofu

In 2023 Terraform's licence changed, and an open-source fork called **OpenTofu** was
created. They are compatible: the same configuration language, the same commands, the
same providers. `tofu plan` and `terraform plan` do the same thing.

Which one a project uses is a licensing decision, not a technical one. Everything above
applies to both.
