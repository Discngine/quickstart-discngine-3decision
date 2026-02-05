# Data Migration Module

One-time Oracle Data Pump import from Discngine's S3 bucket (`dng-psilo-license`) to RDS Oracle.

## Cross-Account Setup

Since the S3 bucket is in Discngine's AWS account, a bucket policy update is required:

1. **Apply terraform** (creates IAM role for RDS)
2. **Get the role ARN**: `terraform output data_migration_rds_role_arn`
3. **Send to Discngine** to add to bucket policy

Discngine will add this to `dng-psilo-license` bucket policy:

```json
{
  "Sid": "AllowCustomerRDS",
  "Effect": "Allow",
  "Principal": { "AWS": "<CUSTOMER_RDS_ROLE_ARN>" },
  "Action": ["s3:GetObject", "s3:ListBucket", "s3:GetBucketLocation"],
  "Resource": ["arn:aws:s3:::dng-psilo-license", "arn:aws:s3:::dng-psilo-license/*"]
}
```

## Usage

1. Upload dump file (Discngine does this):

```bash
aws s3 cp export.dmp s3://dng-psilo-license/migrations/<customer>/export.dmp
```

1. Configure in tfvars:

```hcl
data_migration_enabled = true
data_migration_s3_key  = "migrations/<customer>/export.dmp"
```

1. Apply:

```bash
terraform apply
```

1. Monitor:

```bash
kubectl logs -n tdecision job/data-migration -f
```

## Variables

| Name | Description | Required |
|------|-------------|----------|
| `run_data_migration` | Run the migration job | Yes |
| `s3_key` | Path to dump in dng-psilo-license bucket | Yes |

## Hardcoded Settings

- **S3 Bucket**: `dng-psilo-license` (Discngine account)
- **Target Schema**: `PD_T1_DNG_THREEDECISION`
- **Namespace**: `tdecision`
- **Timeout**: `24 hours`
- **Auto-cleanup**: `30 minutes` after completion

### impdp Options (hardcoded)

- **tables**: `structure_cavity_feature,structure_cavity_feature_pair`
- **remap_table**: `structure_cavity_feature_pair:structure_cavity_feature_pair_updated,structure_cavity_feature:structure_cavity_feature_updated`
- **exclude**: `INDEX,CONSTRAINT,REF_CONSTRAINT,TRIGGER,STATISTICS`
- **table_exists_action**: `skip`
- **access_method**: `external_table`
