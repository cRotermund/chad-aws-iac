# paprika-mcp

Terraform stack for the AWS assets used by
[paprika-mcp-go](https://github.com/cRotermund/paprika-mcp-go): a private S3 bucket
for the recipe index snapshot and an IAM role the pod assumes through the k3s
service-account OIDC issuer.

The role can read and write one object (`snapshot_key`) and list the bucket
restricted to that key. The server needs nothing else.

## Deploy

```bash
cp ../../backend.hcl.example backend.hcl   # set key = "apps/paprika-mcp/terraform.tfstate"
cp terraform.tfvars.example terraform.tfvars
terraform init -backend-config=backend.hcl
terraform apply
```

The homelab stack must be applied first (it owns the IAM OIDC provider).

## Wiring the pod

The cluster has no EKS pod-identity webhook, so the Deployment projects the
token itself. The AWS SDK's default credential chain picks up these variables
with no code change. Values come from `terraform output`.

```yaml
spec:
  serviceAccountName: paprika-mcp-go        # must match service_account_name
  containers:
    - name: paprika-mcp-go
      env:
        - { name: INDEX_STORE,  value: s3 }
        - { name: INDEX_S3_BUCKET, value: <bucket_name> }
        - { name: AWS_REGION, value: us-east-1 }
        - { name: AWS_ROLE_ARN, value: <role_arn> }
        - { name: AWS_WEB_IDENTITY_TOKEN_FILE, value: /var/run/secrets/aws/token }
      volumeMounts:
        - { name: aws-token, mountPath: /var/run/secrets/aws, readOnly: true }
  volumes:
    - name: aws-token
      projected:
        sources:
          - serviceAccountToken:
              audience: sts.amazonaws.com
              expirationSeconds: 3600
              path: token
```

The ServiceAccount must live in `service_account_namespace`
(`chad-applications`). Neither the role ARN nor the bucket name is secret.
