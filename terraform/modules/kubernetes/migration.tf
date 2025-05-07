resource "kubernetes_config_map" "export_dump" {
  count  = var.db_migration ? 1 : 0
  metadata {
    name      = "oracle-export-script"
    namespace = "tools"
  }

  data = {
    "export.sql" = <<-EOT
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
    EOT
  }
}


resource "kubernetes_pod" "sqlplus" {
  count  = var.db_migration ? 1 : 0
  metadata {
    name      = "sqlplus"
    namespace = "tools"
    labels = {
      role = "help"
      app  = "sqlplus"
    }
  }

  spec {
    container {
      name  = "sqlplus"
      image = "fra.ocir.io/discngine1/oracle/instantclient:23"

      command = ["/bin/bash", "-c"]
      args    = [<<-EOC
        set -e
        echo "Running export script..."
        /home/sqlcl/sqlcl/bin/sql ADMIN/$${SYS_DB_PASSWD}@$${CONNECTION_STRING} @/export/export.sql
        echo "Export complete. Watching log output..."
        while true; do
          /home/sqlcl/sqlcl/bin/sql ADMIN/$${SYS_DB_PASSWD}@$${CONNECTION_STRING} \
            "SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF; SELECT text FROM table(rdsadmin.rds_file_util.read_text_file('DATA_PUMP_DIR','pd_t1_export.log'));"
          sleep 10
        done
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
        name = kubernetes_config_map.export_dump.metadata[0].name
      }
    }
  }

  depends_on = [
    kubernetes_namespace.tools_namespace,
    kubectl_manifest.ClusterExternalSecret
  ]
}
