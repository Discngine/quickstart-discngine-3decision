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
  s3_bucket      = "dng-3dec-dump-${var.region}"
  target_schema  = "PD_T1_DNG_THREEDECISION"
  namespace      = "tdecision"
  dump_file_name = basename(var.s3_key)
  # S3 download preserves path structure - file will be at DATA_PUMP_DIR/<s3_key>
  dump_file_path    = var.s3_key
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
GRANT READ, WRITE ON DIRECTORY DATA_PUMP_DIR TO PD_T1_DNG_THREEDECISION;
GRANT IMP_FULL_DATABASE TO PD_T1_DNG_THREEDECISION;

-- Show directory info
SELECT directory_name, directory_path FROM dba_directories WHERE directory_name = 'DATA_PUMP_DIR';

EXIT;
SQL

    "import.sh" = <<-SCRIPT
#!/bin/bash
set -e

echo "=== Data Migration Started ==="
echo "S3 Source: s3://${local.s3_bucket}/${var.s3_key}"
echo "Target Schema: PD_T1_DNG_THREEDECISION"

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
echo "Waiting for S3 download to complete (max 30 min)..."
echo "Task ID: $TASK_ID"
for i in {1..180}; do
  sleep 10
  
  # Check if download task completed (look for SUCCESS or ERROR in log)
  TASK_STATUS=$(sqlplus -s "ADMIN/$SYS_DB_PASSWD@$CONNECTION" << EOSQL
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SELECT CASE 
  WHEN COUNT(*) > 0 THEN 'COMPLETED'
  ELSE 'RUNNING'
END
FROM TABLE(rdsadmin.rds_file_util.read_text_file('BDUMP', 'dbtask-$TASK_ID.log'))
WHERE text LIKE '%finished successfully%' OR text LIKE '%ERROR%' OR text LIKE '%The task failed%';
EXIT;
EOSQL
)
  TASK_STATUS=$(echo $TASK_STATUS | tr -d '[:space:]')
  ELAPSED_MIN=$(($i * 10 / 60))
  
  # Simple progress indicator every 30 seconds
  if [ $(($i % 3)) -eq 0 ]; then
    echo "[$ELAPSED_MIN min] Downloading..."
  fi
  
  if [ "$TASK_STATUS" = "COMPLETED" ]; then
    echo ""
    echo "=== Download task log ==="
    sqlplus -s "ADMIN/$SYS_DB_PASSWD@$CONNECTION" << EOSQL
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 100
SET LINESIZE 200
SELECT text FROM TABLE(rdsadmin.rds_file_util.read_text_file('BDUMP', 'dbtask-$TASK_ID.log'));
EXIT;
EOSQL
    
    # Check if it was an error
    ERROR_CHECK=$(sqlplus -s "ADMIN/$SYS_DB_PASSWD@$CONNECTION" << EOSQL
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SELECT COUNT(*) FROM TABLE(rdsadmin.rds_file_util.read_text_file('BDUMP', 'dbtask-$TASK_ID.log'))
WHERE text LIKE '%ERROR%' OR text LIKE '%The task failed%';
EXIT;
EOSQL
)
    ERROR_CHECK=$(echo $ERROR_CHECK | tr -d '[:space:]')
    if [ "$ERROR_CHECK" != "0" ]; then
      echo "ERROR: S3 download task failed!"
      exit 1
    fi
    
    echo "Download completed successfully!"
    # List all files to see where it was placed
    echo "Listing DATA_PUMP_DIR contents:"
    sqlplus -s "ADMIN/$SYS_DB_PASSWD@$CONNECTION" << EOSQL
SET LINESIZE 200
COLUMN filename FORMAT A60
COLUMN size_gb FORMAT A12
SELECT filename, ROUND(filesize/1024/1024/1024, 2) || ' GB' AS size_gb, mtime 
FROM TABLE(rdsadmin.rds_file_util.listdir('DATA_PUMP_DIR')) 
ORDER BY mtime DESC;
EXIT;
EOSQL
    break
  fi
  
  if [ $i -eq 180 ]; then
    echo "ERROR: Timeout waiting for S3 download to complete (30 min)"
    echo "Final task log:"
    sqlplus -s "ADMIN/$SYS_DB_PASSWD@$CONNECTION" << EOSQL
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SET LINESIZE 200
SELECT text FROM TABLE(rdsadmin.rds_file_util.read_text_file('BDUMP', 'dbtask-$TASK_ID.log'));
EXIT;
EOSQL
    echo "Listing DATA_PUMP_DIR contents:"
    sqlplus -s "ADMIN/$SYS_DB_PASSWD@$CONNECTION" << EOSQL
SET LINESIZE 200
COLUMN filename FORMAT A50
COLUMN size_gb FORMAT A12
SELECT filename, ROUND(filesize/1024/1024/1024, 2) || ' GB' AS size_gb, mtime FROM TABLE(rdsadmin.rds_file_util.listdir('DATA_PUMP_DIR')) ORDER BY mtime DESC;
EXIT;
EOSQL
    exit 1
  fi
done

# List files in DATA_PUMP_DIR after download
echo "Files in DATA_PUMP_DIR after download:"
sqlplus -s "ADMIN/$SYS_DB_PASSWD@$CONNECTION" << EOSQL
SET LINESIZE 200
COLUMN filename FORMAT A50
COLUMN size_gb FORMAT A12
SELECT filename, ROUND(filesize/1024/1024/1024, 2) || ' GB' AS size_gb, mtime FROM TABLE(rdsadmin.rds_file_util.listdir('DATA_PUMP_DIR')) ORDER BY mtime DESC;
EXIT;
EOSQL

# Detect the .dmp file in DATA_PUMP_DIR
DUMP_FILE=$(sqlplus -s "ADMIN/$SYS_DB_PASSWD@$CONNECTION" << EOSQL
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SELECT filename FROM TABLE(rdsadmin.rds_file_util.listdir('DATA_PUMP_DIR')) 
WHERE filename LIKE '%.dmp' 
ORDER BY mtime DESC
FETCH FIRST 1 ROW ONLY;
EXIT;
EOSQL
)
DUMP_FILE=$(echo $DUMP_FILE | tr -d '[:space:]')
echo "Detected dump file: $DUMP_FILE"

if [ -z "$DUMP_FILE" ]; then
  echo "ERROR: No .dmp file found in DATA_PUMP_DIR"
  exit 1
fi

# Clean up old import log files to avoid conflicts
echo "Cleaning up old log files..."
LOG_FILE="datapump_import.log"
sqlplus -s "ADMIN/$SYS_DB_PASSWD@$CONNECTION" << EOSQL
SET SERVEROUTPUT ON
BEGIN
  UTL_FILE.FREMOVE('DATA_PUMP_DIR', '$LOG_FILE');
  DBMS_OUTPUT.PUT_LINE('Removed old $LOG_FILE');
EXCEPTION 
  WHEN OTHERS THEN 
    DBMS_OUTPUT.PUT_LINE('No old log file to remove');
END;
/
EXIT;
EOSQL

# Count tables BEFORE import
echo "Counting tables BEFORE import..."
TABLES_BEFORE=$(sqlplus -s "ADMIN/$SYS_DB_PASSWD@$CONNECTION" << EOSQL
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SELECT COUNT(*) FROM DBA_TABLES WHERE OWNER='PD_T1_DNG_THREEDECISION';
EXIT;
EOSQL
)
TABLES_BEFORE=$(echo $TABLES_BEFORE | tr -d '[:space:]')
echo "Tables BEFORE import: $TABLES_BEFORE"

# Verify dump file exists and check DATA_PUMP_DIR
echo "Verifying dump file in DATA_PUMP_DIR..."
sqlplus -s "ADMIN/$SYS_DB_PASSWD@$CONNECTION" << EOSQL
SET SERVEROUTPUT ON SIZE UNLIMITED
DECLARE
  v_fexists BOOLEAN;
  v_fsize NUMBER;
  v_bsize NUMBER;
BEGIN
  UTL_FILE.FGETATTR('DATA_PUMP_DIR', '$DUMP_FILE', v_fexists, v_fsize, v_bsize);
  IF v_fexists THEN
    DBMS_OUTPUT.PUT_LINE('Dump file exists: $DUMP_FILE');
    DBMS_OUTPUT.PUT_LINE('File size: ' || v_fsize || ' bytes');
  ELSE
    DBMS_OUTPUT.PUT_LINE('ERROR: Dump file NOT found: $DUMP_FILE');
  END IF;
END;
/

-- Check directory path
SELECT directory_path FROM dba_directories WHERE directory_name = 'DATA_PUMP_DIR';
EXIT;
EOSQL

# Run import using DBMS_DATAPUMP
echo "Running DBMS_DATAPUMP import..."
echo "Using dump file: $DUMP_FILE"
echo "Log file: $LOG_FILE"
sqlplus -s "ADMIN/$SYS_DB_PASSWD@$CONNECTION" << EOSQL
SET SERVEROUTPUT ON SIZE UNLIMITED
DECLARE
  v_hdnl NUMBER;
BEGIN
  DBMS_OUTPUT.PUT_LINE('Opening Data Pump job...');
  v_hdnl := DBMS_DATAPUMP.OPEN( 
    operation => 'IMPORT', 
    job_mode  => 'TABLE', 
    job_name  => null);
  DBMS_OUTPUT.PUT_LINE('Job handle: ' || v_hdnl);
  
  DBMS_OUTPUT.PUT_LINE('Adding dump file...');
  DBMS_DATAPUMP.ADD_FILE( 
    handle    => v_hdnl, 
    filename  => '$DUMP_FILE', 
    directory => 'DATA_PUMP_DIR', 
    filetype  => 1);
  DBMS_OUTPUT.PUT_LINE('Dump file added.');
  
  -- Skip log file for now to test if that's the issue
  DBMS_DATAPUMP.ADD_FILE( 
    handle    => v_hdnl, 
    filename  => '$LOG_FILE', 
    directory => 'DATA_PUMP_DIR', 
    filetype  => dbms_datapump.ku\$_file_type_log_file);
  
  DBMS_OUTPUT.PUT_LINE('Adding metadata filters...');
  DBMS_DATAPUMP.METADATA_FILTER(v_hdnl, 'EXCLUDE_PATH_LIST', '''INDEX'',''CONSTRAINT'',''REF_CONSTRAINT'',''TRIGGER'',''STATISTICS'',''GRANT''');
  
  -- Remap tables to new names
  DBMS_DATAPUMP.METADATA_REMAP(v_hdnl, 'REMAP_TABLE', 'PD_T1_DNG_THREEDECISION.STRUCTURE_CAVITY_FEATURE_PAIR', 'STRUCTURE_CAVITY_FEATURE_PAIR_UPDATED');
  DBMS_DATAPUMP.METADATA_REMAP(v_hdnl, 'REMAP_TABLE', 'PD_T1_DNG_THREEDECISION.STRUCTURE_CAVITY_FEATURE', 'STRUCTURE_CAVITY_FEATURE_UPDATED');
  
  -- Handle existing tables
  DBMS_DATAPUMP.SET_PARAMETER(v_hdnl, 'TABLE_EXISTS_ACTION', 'SKIP');
  DBMS_OUTPUT.PUT_LINE('Filters added.');
  
  DBMS_OUTPUT.PUT_LINE('Starting job...');
  DBMS_DATAPUMP.START_JOB(v_hdnl);
  DBMS_OUTPUT.PUT_LINE('Import job started, detaching...');
  DBMS_DATAPUMP.DETACH(v_hdnl);
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('ERROR: ' || SQLERRM);
    DBMS_OUTPUT.PUT_LINE('Error at: ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    -- Don't re-raise, let the job run
END;
/
EXIT;
EOSQL

echo "Data Pump import job started (asynchronous)."
echo "Waiting for import to complete (max 120 min)..."

# Poll until Data Pump job finishes (COMPLETED / NOT RUNNING) or timeout
for i in {1..360}; do
  sleep 20

  JOB_STATE=$(sqlplus -s "ADMIN/$SYS_DB_PASSWD@$CONNECTION" << EOSQL
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SELECT NVL(
  (SELECT state FROM dba_datapump_jobs
   WHERE owner_name = 'ADMIN'
     AND operation = 'IMPORT'
     AND ROWNUM = 1),
  'NOT RUNNING')
FROM dual;
EXIT;
EOSQL
)
  JOB_STATE=$(echo $JOB_STATE | tr -d '[:space:]')
  ELAPSED_MIN=$(( i * 20 / 60 ))

  # Progress every ~2 minutes
  if [ $(( i % 6 )) -eq 0 ]; then
    echo "[$ELAPSED_MIN min] Data Pump state: $JOB_STATE"
  fi

  # Job done when no longer present or explicitly completed
  if [ "$JOB_STATE" = "NOT RUNNING" ] || [ "$JOB_STATE" = "COMPLETED" ]; then
    echo "Data Pump job finished after ~$ELAPSED_MIN min (state: $JOB_STATE)."
    break
  fi

  if [ $i -eq 360 ]; then
    echo "ERROR: Timeout waiting for Data Pump import (120 min)"
    echo "Last state: $JOB_STATE"
    # Show log before exiting
    sqlplus -s "ADMIN/$SYS_DB_PASSWD@$CONNECTION" << EOSQL
SET SERVEROUTPUT ON SIZE UNLIMITED
BEGIN
  FOR rec IN (SELECT text FROM TABLE(rdsadmin.rds_file_util.read_text_file('DATA_PUMP_DIR', '$LOG_FILE'))) LOOP
    DBMS_OUTPUT.PUT_LINE(rec.text);
  END LOOP;
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Note: Log file not readable');
END;
/
EXIT;
EOSQL
    exit 1
  fi
done

# Count tables AFTER import
echo "Counting tables AFTER import..."
TABLES_AFTER=$(sqlplus -s "ADMIN/$SYS_DB_PASSWD@$CONNECTION" << EOSQL
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SELECT COUNT(*) FROM DBA_TABLES WHERE OWNER='PD_T1_DNG_THREEDECISION';
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

# Show final status and import log
echo "Checking import results..."
sqlplus -s "ADMIN/$SYS_DB_PASSWD@$CONNECTION" << EOSQL
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 200
SET PAGESIZE 1000

-- List Data Pump files in directory
PROMPT === DATA_PUMP_DIR files ===
SELECT filename FROM TABLE(rdsadmin.rds_file_util.listdir('DATA_PUMP_DIR')) WHERE filename LIKE '%.log' OR filename LIKE '%.dmp';

-- Display import log content
PROMPT === Import Log ===
BEGIN
  FOR rec IN (SELECT text FROM TABLE(rdsadmin.rds_file_util.read_text_file('DATA_PUMP_DIR', '$LOG_FILE'))) LOOP
    DBMS_OUTPUT.PUT_LINE(rec.text);
  END LOOP;
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Note: Log file not found or not readable');
END;
/

EXIT;
EOSQL

# Validate that the two expected tables exist and have data
echo "=== Validating imported tables ==="
VALIDATION=$(sqlplus -s "ADMIN/$SYS_DB_PASSWD@$CONNECTION" << EOSQL
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SELECT TABLE_NAME || ':' || NUM_ROWS
FROM (
  SELECT t.TABLE_NAME,
         (SELECT COUNT(*) FROM PD_T1_DNG_THREEDECISION.STRUCTURE_CAVITY_FEATURE_UPDATED WHERE ROWNUM <= 1) AS NUM_ROWS
  FROM DBA_TABLES t
  WHERE t.OWNER = 'PD_T1_DNG_THREEDECISION' AND t.TABLE_NAME = 'STRUCTURE_CAVITY_FEATURE_UPDATED'
  UNION ALL
  SELECT t.TABLE_NAME,
         (SELECT COUNT(*) FROM PD_T1_DNG_THREEDECISION.STRUCTURE_CAVITY_FEATURE_PAIR_UPDATED WHERE ROWNUM <= 1) AS NUM_ROWS
  FROM DBA_TABLES t
  WHERE t.OWNER = 'PD_T1_DNG_THREEDECISION' AND t.TABLE_NAME = 'STRUCTURE_CAVITY_FEATURE_PAIR_UPDATED'
);
EXIT;
EOSQL
)

TABLE_COUNT=$(echo "$VALIDATION" | grep -c ':' || true)
EMPTY_COUNT=$(echo "$VALIDATION" | grep ':0$' | wc -l || true)

echo "$VALIDATION"

if [ "$TABLE_COUNT" -ne 2 ]; then
  echo "ERROR: Expected 2 tables, found $TABLE_COUNT"
  echo "Data migration FAILED - required tables are missing."
  exit 1
fi

if [ "$EMPTY_COUNT" -gt 0 ]; then
  echo "ERROR: One or more tables have 0 rows"
  echo "Data migration FAILED - tables are empty."
  exit 1
fi

echo "SUCCESS: Both tables exist and have data."
echo "=== Import Complete ==="

# Cleanup
echo "Cleaning up..."
sqlplus -s "ADMIN/$SYS_DB_PASSWD@$CONNECTION" << EOSQL
REVOKE IMP_FULL_DATABASE FROM PD_T1_DNG_THREEDECISION;
BEGIN
  UTL_FILE.FREMOVE('DATA_PUMP_DIR', '$DUMP_FILE');
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
  DBMS_STATS.GATHER_SCHEMA_STATS('PD_T1_DNG_THREEDECISION', options => 'GATHER AUTO');
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
# Depends on s3_role_association_id to ensure IAM role is attached before running
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
    ttl_seconds_after_finished = 604800 # 1 week
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

  wait_for_completion = true
  timeouts {
    create = "150m"
  }
}
