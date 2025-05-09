resource "kubernetes_config_map" "export_dump" {
  count = var.db_migration ? 1 : 0
  metadata {
    name      = "oracle-export-script"
    namespace = "tools"
  }

  data = {
    "check_file.sql"     = <<-EOT
      SET HEADING OFF;
      SET FEEDBACK OFF;
      SELECT CASE WHEN COUNT(*) > 0 THEN 'YES' ELSE 'NO' END
      FROM table(RDSADMIN.RDS_FILE_UTIL.LISTDIR('DATA_PUMP_DIR'))
      WHERE filename = 'pd_t1_dng_threedecision.dmp' AND type = 'file';
      exit;
    EOT
    "get_export_log.sql" = <<-EOT
      SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF;
      SELECT text FROM table(rdsadmin.rds_file_util.read_text_file('DATA_PUMP_DIR','pd_t1_export.log'));
      exit;
    EOT
    "upload_to_s3.sql"   = <<-EOT
      SELECT rdsadmin.rdsadmin_s3_tasks.upload_to_s3(
            p_bucket_name    =>  '${var.export_bucket_name}', 
            p_directory_name =>  'DATA_PUMP_DIR')
      AS TASK_ID FROM DUAL;
      exit;
    EOT
    "export.sql"         = <<-EOT
      DECLARE
        v_hdnl NUMBER;
      BEGIN
        v_hdnl := DBMS_DATAPUMP.OPEN(
          operation => 'EXPORT',
          job_mode  => 'SCHEMA',
          job_name  => null
        );
        DBMS_DATAPUMP.ADD_FILE(
          handle    => v_hdnl,
          filename  => 'pd_t1_dng_threedecision.dmp',
          directory => 'DATA_PUMP_DIR',
          filetype  => dbms_datapump.ku$_file_type_dump_file
        );
        DBMS_DATAPUMP.ADD_FILE(
          handle    => v_hdnl,
          filename  => 'pd_t1_export.log',
          directory => 'DATA_PUMP_DIR',
          filetype  => dbms_datapump.ku$_file_type_log_file
        );
        DBMS_DATAPUMP.METADATA_FILTER(v_hdnl, 'SCHEMA_EXPR', 'IN (''PD_T1_DNG_THREEDECISION'')');
        DBMS_DATAPUMP.METADATA_FILTER(
          v_hdnl,
          'EXCLUDE_NAME_EXPR',
          q'[IN (SELECT NAME FROM SYS.OBJ$
                 WHERE TYPE# IN (66,67,74,79,59,62,46)
                 AND OWNER# IN
                   (SELECT USER# FROM SYS.USER$
                    WHERE NAME IN ('RDSADMIN','SYS','SYSTEM','RDS_DATAGUARD','RDSSEC')
                   )
                )
          ]',
          'PROCOBJ'
        );
        DBMS_DATAPUMP.START_JOB(v_hdnl);
      END;
      /
      exit;
    EOT
  }
}


resource "kubernetes_job" "sqlplus" {
  count = var.db_migration ? 1 : 0

  metadata {
    name      = "sqlplus"
    namespace = "tools"
    labels = {
      role = "help"
      app  = "sqlplus"
    }
  }

  spec {
    backoff_limit = 0

    template {
      metadata {
        labels = {
          role = "help"
          app  = "sqlplus"
        }
      }

      spec {
        restart_policy = "Never"

        container {
          name  = "sqlplus"
          image = "fra.ocir.io/discngine1/oracle/instantclient:23"

          command = ["/bin/bash", "-c"]
          args = [<<-EOC
            set -e
            echo "Checking if export dump file exists..."

            # Check if the dump file already exists in the DATA_PUMP_DIR directory using RDS_FILE_UTIL.LISTDIR
            FILE_EXISTS=$(sqlplus -S ADMIN/$${SYS_DB_PASSWD}@$${CONNECTION_STRING} @/scripts/check_file.sql | tr -d '[:space:]')

            if [ "$FILE_EXISTS" = "YES" ]; then
              echo "Export dump file already exists in the database. Skipping export."
            else
              echo "Running export script..."
              sqlplus ADMIN/$${SYS_DB_PASSWD}@$${CONNECTION_STRING} @/scripts/export.sql 
              echo "Export complete. Watching log output..."
              while true; do
                sqlplus ADMIN/$${SYS_DB_PASSWD}@$${CONNECTION_STRING} @/scripts/get_export_log.sql
                EXPORT_STATUS=$(sqlplus -S ADMIN/$${SYS_DB_PASSWD}@$${CONNECTION_STRING} @/scripts/get_export_log.sql)

                # If export is complete (you can replace this condition with the actual success condition from your log)
                if [[ "$EXPORT_STATUS" == *"successfully completed"* ]]; then
                  break
                fi

                sleep 10
              done
              echo "Export completed successfully. Uploading to S3..."
              
              # Run the upload to S3 command
              sqlplus -S ADMIN/$${SYS_DB_PASSWD}@$${CONNECTION_STRING} @/scripts/upload_to_s3.sql

              echo "S3 upload task started."
              echo "You can track the status of the upload task with the following sql command. (replace <id> with the task id returned just above)"
              echo "SELECT text FROM table(rdsadmin.rds_file_util.read_text_file('BDUMP','dbtask-<id>.log'));"
              echo "You can run this command by accessing the database with the following command: kubectl exec -it deploy/sqlcl -n tools -- /bin/bash -c \"eval \\\$sqs"\"
            fi
          EOC
          ]

          env_from {
            secret_ref {
              name = "database-secrets"
            }
          }

          env {
            name  = "CONNECTION_STRING"
            value = local.connection_string
          }

          volume_mount {
            name       = "export-script"
            mount_path = "/scripts"
            read_only  = true
          }

          resources {
            requests = {
              cpu    = "10m"
              memory = "256Mi"
            }
          }
        }

        volume {
          name = "export-script"

          config_map {
            name = kubernetes_config_map.export_dump[0].metadata[0].name
          }
        }
      }
    }
  }
  wait_for_completion = false

  depends_on = [
    kubernetes_namespace.tools_namespace,
    kubectl_manifest.ClusterExternalSecret
  ]
}
