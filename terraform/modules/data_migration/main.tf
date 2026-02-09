# Data Migration Module - Simplified main.tf
# One-time Oracle Data Pump import from S3 (dng-psilo-license bucket)

terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    aws = {
      source = "hashicorp/aws"
    }
  }
}

locals {
  s3_bucket         = "dng-psilo-license"
  target_schema     = "PD_T1_DNG_THREEDECISION"
  namespace         = "tdecision"
  dump_file_name    = basename(var.s3_key)
  connection_string = "${var.db_endpoint}/${var.db_name}"
}

# ConfigMap with migration scripts
resource "kubernetes_config_map" "migration_scripts" {
  count = var.run_data_migration ? 1 : 0

  metadata {
    name      = "migration-scripts"
    namespace = local.namespace
  }

  data = {
    "prepare_db.sql" = <<-SQL
SET ECHO ON
SET SERVEROUTPUT ON

-- Create Data Pump directory
GRANT READ, WRITE ON DIRECTORY DATA_PUMP_DIR TO ${local.target_schema};
GRANT IMP_FULL_DATABASE TO ${local.target_schema};

-- Show directory info
SELECT directory_name, directory_path FROM dba_directories WHERE directory_name = 'DATA_PUMP_DIR';

EXIT;
SQL

    "import.sh" = <<-SCRIPT
#!/bin/bash
set -e

echo "=== Data Migration Started ==="
echo "S3 Source: s3://${local.s3_bucket}/${var.s3_key}"
echo "Target Schema: ${local.target_schema}"

# Wait for secrets
echo "Waiting for database credentials..."
for i in {1..60}; do
  [ -f /secrets/DB_PASSWD ] && break
  sleep 5
done
[ ! -f /secrets/DB_PASSWD ] && echo "ERROR: Secrets not found" && exit 1

DB_PASSWD=$(cat /secrets/DB_PASSWD)
SYS_DB_PASSWD=$(cat /secrets/SYS_DB_PASSWD)
CONNECTION="${var.db_endpoint}/${var.db_name}"

# Prepare database
echo "Preparing database..."
sqlplus -s "ADMIN/$SYS_DB_PASSWD@$CONNECTION" @/scripts/prepare_db.sql

# Download dump file from S3 to RDS
echo "Downloading dump file to RDS DATA_PUMP_DIR..."
TASK_ID=$(sqlplus -s "ADMIN/$SYS_DB_PASSWD@$CONNECTION" << EOSQL
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SET SERVEROUTPUT ON SIZE UNLIMITED
DECLARE
  v_task_id VARCHAR2(64);
BEGIN
  v_task_id := rdsadmin.rdsadmin_s3_tasks.download_from_s3(
    p_bucket_name    => '${local.s3_bucket}',
    p_s3_prefix      => '${var.s3_key}',
    p_directory_name => 'DATA_PUMP_DIR'
  );
  DBMS_OUTPUT.PUT_LINE(v_task_id);
END;
/
EXIT;
EOSQL
)
TASK_ID=$(echo $TASK_ID | tr -d '[:space:]')
echo "Download task ID: $TASK_ID"

# Wait for S3 download to complete by checking task status
echo "Waiting for S3 download to complete (checking task status, max 30 min)..."
for i in {1..180}; do
  sleep 10
  echo "Checking download status (attempt $i/180, $(($i * 10 / 60)) min elapsed)..."
  
  # Check if file exists in DATA_PUMP_DIR
  FILE_EXISTS=$(sqlplus -s "ADMIN/$SYS_DB_PASSWD@$CONNECTION" << EOSQL
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SELECT COUNT(*) FROM TABLE(rdsadmin.rds_file_util.listdir('DATA_PUMP_DIR')) WHERE filename = '${local.dump_file_name}';
EXIT;
EOSQL
)
  FILE_EXISTS=$(echo $FILE_EXISTS | tr -d '[:space:]')
  
  if [ "$FILE_EXISTS" = "1" ]; then
    echo "Dump file found in DATA_PUMP_DIR!"
    break
  fi
  
  if [ $i -eq 180 ]; then
    echo "ERROR: Timeout waiting for S3 download to complete (30 min)"
    echo "Listing DATA_PUMP_DIR contents:"
    sqlplus -s "ADMIN/$SYS_DB_PASSWD@$CONNECTION" << EOSQL
SELECT filename, filesize, mtime FROM TABLE(rdsadmin.rds_file_util.listdir('DATA_PUMP_DIR'));
EXIT;
EOSQL
    exit 1
  fi
done

# List files in DATA_PUMP_DIR after download
echo "Files in DATA_PUMP_DIR after download:"
sqlplus -s "ADMIN/$SYS_DB_PASSWD@$CONNECTION" << EOSQL
SET LINESIZE 200
SELECT filename, filesize, mtime FROM TABLE(rdsadmin.rds_file_util.listdir('DATA_PUMP_DIR')) ORDER BY mtime DESC;
EXIT;
EOSQL

# Count tables BEFORE import
echo "Counting tables BEFORE import..."
TABLES_BEFORE=$(sqlplus -s "ADMIN/$SYS_DB_PASSWD@$CONNECTION" << EOSQL
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SELECT COUNT(*) FROM DBA_TABLES WHERE OWNER='${local.target_schema}';
EXIT;
EOSQL
)
TABLES_BEFORE=$(echo $TABLES_BEFORE | tr -d '[:space:]')
echo "Tables BEFORE import: $TABLES_BEFORE"

# Run import using DBMS_DATAPUMP
echo "Running DBMS_DATAPUMP import..."
sqlplus -s "ADMIN/$SYS_DB_PASSWD@$CONNECTION" << EOSQL
SET SERVEROUTPUT ON SIZE UNLIMITED
DECLARE
  v_hdnl NUMBER;
BEGIN
  v_hdnl := DBMS_DATAPUMP.OPEN( 
    operation => 'IMPORT', 
    job_mode  => 'SCHEMA', 
    job_name  => null);
  DBMS_DATAPUMP.ADD_FILE( 
    handle    => v_hdnl, 
    filename  => '${local.dump_file_name}', 
    directory => 'DATA_PUMP_DIR', 
    filetype  => 1);
  DBMS_DATAPUMP.ADD_FILE( 
    handle    => v_hdnl, 
    filename  => 'import_migration.log', 
    directory => 'DATA_PUMP_DIR', 
    filetype  => 2);
  DBMS_DATAPUMP.METADATA_FILTER(v_hdnl,'SCHEMA_EXPR','IN (''${local.target_schema}'')');
  DBMS_DATAPUMP.START_JOB(v_hdnl);
END;
/
EXIT;
EOSQL

echo "Data Pump import job started (asynchronous)."
echo "Waiting for import to complete..."
sleep 120

# Count tables AFTER import
echo "Counting tables AFTER import..."
TABLES_AFTER=$(sqlplus -s "ADMIN/$SYS_DB_PASSWD@$CONNECTION" << EOSQL
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SELECT COUNT(*) FROM DBA_TABLES WHERE OWNER='${local.target_schema}';
EXIT;
EOSQL
)
TABLES_AFTER=$(echo $TABLES_AFTER | tr -d '[:space:]')
echo "Tables AFTER import: $TABLES_AFTER"

# Calculate difference
TABLES_ADDED=$((TABLES_AFTER - TABLES_BEFORE))
echo "========================================="
echo "IMPORT SUMMARY:"
echo "  Tables BEFORE: $TABLES_BEFORE"
echo "  Tables AFTER:  $TABLES_AFTER"
echo "  Tables ADDED:  $TABLES_ADDED"
echo "========================================="

# Check import status and show log
echo "Checking import status..."
sqlplus -s "ADMIN/$SYS_DB_PASSWD@$CONNECTION" << EOSQL
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 200
SET PAGESIZE 0

-- List Data Pump files in directory
SELECT 'DATA_PUMP_DIR files: ' || filename FROM TABLE(rdsadmin.rds_file_util.listdir('DATA_PUMP_DIR')) WHERE filename LIKE '%.log' OR filename LIKE '%.dmp';

-- Try to display import log content (if exists)
BEGIN
  FOR rec IN (SELECT text FROM TABLE(rdsadmin.rds_file_util.read_text_file('DATA_PUMP_DIR', 'import_migration.log'))) LOOP
    DBMS_OUTPUT.PUT_LINE(rec.text);
  END LOOP;
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Note: Log file not found or not readable');
END;
/

EXIT;
EOSQL

echo "=== Import Complete ==="

# Cleanup
echo "Cleaning up..."
sqlplus -s "ADMIN/$SYS_DB_PASSWD@$CONNECTION" << EOSQL
REVOKE IMP_FULL_DATABASE FROM ${local.target_schema};
BEGIN
  UTL_FILE.FREMOVE('DATA_PUMP_DIR', '${local.dump_file_name}');
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
  DBMS_STATS.GATHER_SCHEMA_STATS('${local.target_schema}', options => 'GATHER AUTO');
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;
EOSQL

echo "=== Data Migration Complete ==="
SCRIPT
  }
}

# Migration Job
resource "kubernetes_job_v1" "migration" {
  count = var.run_data_migration ? 1 : 0

  metadata {
    name      = "data-migration"
    namespace = local.namespace
    labels = {
      "app.kubernetes.io/name" = "data-migration"
    }
  }

  spec {
    ttl_seconds_after_finished = 1800 # 30 min cleanup
    backoff_limit              = 2
    active_deadline_seconds    = 86400 # 24h timeout

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name" = "data-migration"
        }
      }

      spec {
        restart_policy = "OnFailure"

        container {
          name  = "import"
          image = "fra.ocir.io/discngine1/oracle/instantclient:23"

          command = ["/bin/bash", "-c", "/scripts/import.sh"]

          env {
            name  = "AWS_DEFAULT_REGION"
            value = var.region
          }

          volume_mount {
            name       = "scripts"
            mount_path = "/scripts"
          }

          volume_mount {
            name       = "db-secrets"
            mount_path = "/secrets"
            read_only  = true
          }

          resources {
            requests = {
              cpu    = "1"
              memory = "2Gi"
            }
            limits = {
              cpu    = "2"
              memory = "4Gi"
            }
          }
        }

        volume {
          name = "scripts"
          config_map {
            name         = kubernetes_config_map.migration_scripts[0].metadata[0].name
            default_mode = "0755"
          }
        }

        volume {
          name = "db-secrets"
          secret {
            secret_name = "database-secrets"
          }
        }
      }
    }
  }

  wait_for_completion = false
  timeouts {
    create = "5m"
  }
}

# IAM Role for RDS to access S3
resource "aws_iam_role" "rds_s3" {
  count       = var.run_data_migration ? 1 : 0
  name_prefix = "3decision-rds-s3-datapump-access"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "rds.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "rds_s3" {
  count = var.run_data_migration ? 1 : 0
  name  = "s3-access"
  role  = aws_iam_role.rds_s3[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["s3:GetObject", "s3:ListBucket", "s3:GetBucketLocation"]
      Resource = [
        "arn:aws:s3:::${local.s3_bucket}",
        "arn:aws:s3:::${local.s3_bucket}/*"
      ]
    }]
  })
}
