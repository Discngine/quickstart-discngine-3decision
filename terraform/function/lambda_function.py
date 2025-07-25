# Copyright 2018 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

import boto3
import json
import logging
import os
import cx_Oracle
import time

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def lambda_handler(event, context):
    """Secrets Manager RDS Oracle Handler

    This handler uses the single-user rotation scheme to rotate an RDS Oracle user credential. This rotation scheme
    logs into the database as the user and rotates the user's own password, immediately invalidating the user's
    previous password.

    The Secret SecretString is expected to be a JSON string with the following format:
    {
        'engine': <required: must be set to 'oracle'>,
        'host': <required: instance host name>,
        'username': <required: username>,
        'password': <required: password>,
        'dbname': <required: database name>,
        'port': <optional: if not specified, default port 1521 will be used>
    }

    Args:
        event (dict): Lambda dictionary of event parameters. These keys must include the following:
            - SecretId: The secret ARN or identifier
            - ClientRequestToken: The ClientRequestToken of the secret version
            - Step: The rotation step (one of createSecret, setSecret, testSecret, or finishSecret)

        context (LambdaContext): The Lambda runtime information

    Raises:
        ResourceNotFoundException: If the secret with the specified arn and stage does not exist

        ValueError: If the secret is not properly configured for rotation

        KeyError: If the secret json does not contain the expected keys

    """
    arn = event['SecretId']
    token = event['ClientRequestToken']
    step = event['Step']

    # Setup the client
    service_client = boto3.client('secretsmanager', endpoint_url=os.environ['SECRETS_MANAGER_ENDPOINT'])

    # Make sure the version is staged correctly
    metadata = service_client.describe_secret(SecretId=arn)
    if "RotationEnabled" in metadata and not metadata['RotationEnabled']:
        logger.error("Secret %s is not enabled for rotation" % arn)
        raise ValueError("Secret %s is not enabled for rotation" % arn)
    versions = metadata['VersionIdsToStages']
    if token not in versions:
        logger.error("Secret version %s has no stage for rotation of secret %s." % (token, arn))
        raise ValueError("Secret version %s has no stage for rotation of secret %s." % (token, arn))
    if "AWSCURRENT" in versions[token]:
        logger.info("Secret version %s already set as AWSCURRENT for secret %s." % (token, arn))
        return
    elif "AWSPENDING" not in versions[token]:
        logger.error("Secret version %s not set as AWSPENDING for rotation of secret %s." % (token, arn))
        raise ValueError("Secret version %s not set as AWSPENDING for rotation of secret %s." % (token, arn))

    # Call the appropriate step
    if step == "createSecret":
        create_secret(service_client, arn, token)

    elif step == "setSecret":
        set_secret(service_client, arn, token)

    elif step == "testSecret":
        test_secret(service_client, arn, token)

    elif step == "finishSecret":
        finish_secret(service_client, arn, token)

    else:
        logger.error("lambda_handler: Invalid step parameter %s for secret %s" % (step, arn))
        raise ValueError("Invalid step parameter %s for secret %s" % (step, arn))


def create_secret(service_client, arn, token):
    """Generate a new secret

    This method first checks for the existence of a secret for the passed in token. If one does not exist, it will generate a
    new secret and put it with the passed in token.

    Args:
        service_client (client): The secrets manager service client

        arn (string): The secret ARN or other identifier

        token (string): The ClientRequestToken associated with the secret version

    Raises:
        ValueError: If the current secret is not valid JSON

        KeyError: If the secret json does not contain the expected keys

    """
    # Make sure the current secret exists
    current_dict = get_secret_dict(service_client, arn, "AWSCURRENT")

    # Now try to get the secret version, if that fails, put a new secret
    try:
        get_secret_dict(service_client, arn, "AWSPENDING", token)
        logger.info("createSecret: Successfully retrieved secret for %s." % arn)
    except service_client.exceptions.ResourceNotFoundException:
        # Get exclude characters from environment variable
        exclude_characters = os.environ['EXCLUDE_CHARACTERS'] if 'EXCLUDE_CHARACTERS' in os.environ else '/@"\'\\'
        # Generate a random password
        passwd = service_client.get_random_password(ExcludeCharacters=exclude_characters, PasswordLength=30)
        current_dict['password'] = passwd['RandomPassword']

        # Put the secret
        service_client.put_secret_value(SecretId=arn, ClientRequestToken=token, SecretString=json.dumps(current_dict), VersionStages=['AWSPENDING'])
        logger.info("createSecret: Successfully put secret for ARN %s and version %s." % (arn, token))


def set_secret(service_client, arn, token):
    """Set the pending secret in the database

    This method tries to login to the database with the AWSPENDING secret and returns on success. If that fails, it
    tries to login with the AWSCURRENT and AWSPREVIOUS secrets. If either one succeeds, it sets the AWSPENDING password
    as the user password in the database. Else, it throws a ValueError.

    Args:
        service_client (client): The secrets manager service client

        arn (string): The secret ARN or other identifier

        token (string): The ClientRequestToken associated with the secret version

    Raises:
        ResourceNotFoundException: If the secret with the specified arn and stage does not exist

        ValueError: If the secret is not valid JSON or valid credentials are found to login to the database

        KeyError: If the secret json does not contain the expected keys

    """
    try:
        previous_dict = get_secret_dict(service_client, arn, "AWSPREVIOUS")
    except (service_client.exceptions.ResourceNotFoundException, KeyError):
        previous_dict = None
    current_dict = get_secret_dict(service_client, arn, "AWSCURRENT")
    pending_dict = get_secret_dict(service_client, arn, "AWSPENDING", token)

    # First try to login with the pending secret, if it succeeds, return
    conn = get_connection(pending_dict)
    if conn:
        conn.close()
        logger.info("setSecret: AWSPENDING secret is already set as password in Oracle DB for secret arn %s." % arn)
        return

    # Make sure the user from current and pending match
    if current_dict['username'] != pending_dict['username']:
        logger.error("setSecret: Attempting to modify user %s other than current user %s" % (pending_dict['username'], current_dict['username']))
        raise ValueError("Attempting to modify user %s other than current user %s" % (pending_dict['username'], current_dict['username']))

    # Make sure the host from current and pending match
    if current_dict['host'] != pending_dict['host']:
        logger.error("setSecret: Attempting to modify user for host %s other than current host %s" % (pending_dict['host'], current_dict['host']))
        raise ValueError("Attempting to modify user for host %s other than current host %s" % (pending_dict['host'], current_dict['host']))

    # Now try the current password
    conn = get_connection(current_dict)
    if not conn and previous_dict:
        # If both current and pending do not work, try previous
        conn = get_connection(previous_dict)

        # Make sure the user/host from previous and pending match
        if previous_dict['username'] != pending_dict['username']:
            logger.error("setSecret: Attempting to modify user %s other than previous valid user %s" % (pending_dict['username'], previous_dict['username']))
            raise ValueError("Attempting to modify user %s other than previous valid user %s" % (pending_dict['username'], previous_dict['username']))
        if previous_dict['host'] != pending_dict['host']:
            logger.error("setSecret: Attempting to modify user for host %s other than previous host %s" % (pending_dict['host'], previous_dict['host']))
            raise ValueError("Attempting to modify user for host %s other than previous host %s" % (pending_dict['host'], previous_dict['host']))

    # If we still don't have a connection, raise a ValueError
    if not conn:
        logger.error("setSecret: Unable to log into database with previous, current, or pending secret of secret arn %s" % arn)
        raise ValueError("Unable to log into database with previous, current, or pending secret of secret arn %s" % arn)

    cur = conn.cursor()

    # Escape username via DBMS ENQUOTE_NAME
    cur.execute("SELECT sys.DBMS_ASSERT.enquote_name(:username) FROM DUAL", username=pending_dict['username'])
    escaped_username = cur.fetchone()[0]

    # Passwords cannot have double quotes in Oracle, remove any double quotes to allow the password to be properly escaped
    pending_password = pending_dict['password'].replace("\"", "")

    # Now set the password to the pending password
    sql = "ALTER USER %s IDENTIFIED BY \"%s\"" % (escaped_username, pending_dict['password'])
    cur.execute(sql)
    conn.commit()
    logger.info("setSecret: Successfully set password for user %s in Oracle DB for secret arn %s." % (pending_dict['username'], arn))


def test_secret(service_client, arn, token):
    """Test the pending secret against the database

    This method tries to log into the database with the secrets staged with AWSPENDING and runs
    a permissions check to ensure the user has the corrrect permissions.

    Args:
        service_client (client): The secrets manager service client

        arn (string): The secret ARN or other identifier

        token (string): The ClientRequestToken associated with the secret version

    Raises:
        ResourceNotFoundException: If the secret with the specified arn and stage does not exist

        ValueError: If the secret is not valid JSON or valid credentials are found to login to the database

        KeyError: If the secret json does not contain the expected keys

    """
    # Try to login with the pending secret, if it succeeds, return
    conn = get_connection(get_secret_dict(service_client, arn, "AWSPENDING", token))
    if conn:
        # This is where the lambda will validate the user's permissions. Uncomment/modify the below lines to
        # tailor these validations to your needs
        cur = conn.cursor()
        cur.execute("SELECT SYSDATE FROM DUAL")
        conn.commit()

        logger.info("testSecret: Successfully signed into Oracle DB with AWSPENDING secret in %s." % arn)
        return
    else:
        logger.error("testSecret: Unable to log into database with pending secret of secret ARN %s" % arn)
        raise ValueError("Unable to log into database with pending secret of secret ARN %s" % arn)


def finish_secret(service_client, arn, token):
    """Finish the rotation by marking the pending secret as current

    This method finishes the secret rotation by staging the secret staged AWSPENDING with the AWSCURRENT stage.

    Args:
        service_client (client): The secrets manager service client

        arn (string): The secret ARN or other identifier

        token (string): The ClientRequestToken associated with the secret version

    """
    # First describe the secret to get the current version
    metadata = service_client.describe_secret(SecretId=arn)
    current_version = None
    for version in metadata["VersionIdsToStages"]:
        if "AWSCURRENT" in metadata["VersionIdsToStages"][version]:
            if version == token:
                # The correct version is already marked as current, return
                logger.info("finishSecret: Version %s already marked as AWSCURRENT for %s" % (version, arn))
                return
            current_version = version
            break

    # Finalize by staging the secret version current
    service_client.update_secret_version_stage(SecretId=arn, VersionStage="AWSCURRENT", MoveToVersionId=token, RemoveFromVersionId=current_version)
    logger.info("finishSecret: Successfully set AWSCURRENT stage to version %s for secret %s." % (token, arn))

    # Wait 1 minute, then unlock or reset the account
    time.sleep(60)
    try:
        secret_dict = get_secret_dict(service_client, arn, "AWSCURRENT")
        username = secret_dict['username']
        admin_secret = get_secret_dict(service_client, '3dec-admin-db', 'AWSCURRENT')
        admin_username = admin_secret['username']
        if username == admin_username:
            logger.info(f"finishSecret: Admin account detected, testing connection.")
            unlock_admin_password_if_needed(secret_dict)
            return
        unlock_account_if_needed(secret_dict, admin_secret)
    except Exception as e:
        logger.warning("finishSecret: Failed to unlock/reset account for user %s: %s" % (username if 'username' in locals() else 'unknown', str(e)))


def unlock_account_if_needed(secret_dict, admin_secret):
    """Unlocks a non-admin user using the admin account."""
    username = secret_dict['username']
    password = secret_dict['password']
    admin_port = str(admin_secret['port']) if 'port' in admin_secret else '1521'
    admin_conn = cx_Oracle.connect(admin_secret['username'],
                                  admin_secret['password'],
                                  admin_secret['host'] + ':' + admin_port + '/' + admin_secret['dbname'])
    cur = admin_conn.cursor()
    cur.execute("SELECT sys.DBMS_ASSERT.enquote_name(:username) FROM DUAL", username=username)
    escaped_username = cur.fetchone()[0]
    sql_unlock = "ALTER USER %s IDENTIFIED BY \"%s\" ACCOUNT UNLOCK" % (escaped_username, password)
    cur.execute(sql_unlock)
    admin_conn.commit()
    logger.info("finishSecret: Successfully unlocked account for user %s in Oracle DB after 1 minute (using admin)." % username)
    cur.close()
    admin_conn.close()


def unlock_admin_password_if_needed(secret_dict):
    """For admin user: test connection, and if it fails, reset password via RDS API using env vars."""
    username = secret_dict['username']
    port = str(secret_dict['port']) if 'port' in secret_dict else '1521'
    password = secret_dict['password']
    host = secret_dict['host']
    dbname = secret_dict['dbname']
    db_instance_id = os.environ.get('DB_INSTANCE_IDENTIFIER') or secret_dict.get('db_instance_identifier')
    admin_username_env = os.environ.get('ADMIN_USERNAME')
    try:
        conn = cx_Oracle.connect(username, password, host + ':' + port + '/' + dbname)
        conn.close()
        logger.info(f"finishSecret: Admin account ({username}) connection successful, no unlock/reset needed.")
    except Exception as e:
        logger.warning(f"finishSecret: Admin account ({username}) connection failed, attempting RDS password reset: {str(e)}")
        rds_client = boto3.client('rds')
        if not db_instance_id:
            logger.error("finishSecret: DB_INSTANCE_IDENTIFIER not set in environment or secret for admin password reset.")
        else:
            try:
                rds_client.modify_db_instance(
                    DBInstanceIdentifier=db_instance_id,
                    MasterUserPassword=password,
                    ApplyImmediately=True
                )
                logger.info(f"finishSecret: RDS password reset issued for admin account ({username}) on instance {db_instance_id}.")
            except Exception as rds_e:
                logger.error(f"finishSecret: Failed to reset admin password via RDS API: {str(rds_e)}")


def get_connection(secret_dict):
    """Gets a connection to Oracle DB from a secret dictionary

    This helper function tries to connect to the database grabbing connection info
    from the secret dictionary. If successful, it returns the connection, else None

    Args:
        secret_dict (dict): The Secret Dictionary

    Returns:
        Connection: The cx_Oracle.Connection object if successful. None otherwise

    Raises:
        KeyError: If the secret json does not contain the expected keys

    """
    # Parse and validate the secret JSON string
    port = str(secret_dict['port']) if 'port' in secret_dict else '1521'

    # Try to obtain a connection to the db
    try:
        conn = cx_Oracle.connect(secret_dict['username'],
                                 secret_dict['password'],
                                 secret_dict['host'] + ':' + port + '/' + secret_dict['dbname'])
        logger.info("Successfully established connection as user '%s' with host: '%s'" % (secret_dict['username'], secret_dict['host']))
        return conn
    except (cx_Oracle.DatabaseError, cx_Oracle.OperationalError):
        return None


def get_secret_dict(service_client, arn, stage, token=None):
    """Gets the secret dictionary corresponding for the secret arn, stage, and token

    This helper function gets credentials for the arn and stage passed in and returns the dictionary by parsing the JSON string

    Args:
        service_client (client): The secrets manager service client

        arn (string): The secret ARN or other identifier

        token (string): The ClientRequestToken associated with the secret version, or None if no validation is desired

        stage (string): The stage identifying the secret version

    Returns:
        SecretDictionary: Secret dictionary

    Raises:
        ResourceNotFoundException: If the secret with the specified arn and stage does not exist

        ValueError: If the secret is not valid JSON

    """
    required_fields = ['host', 'username', 'password', 'dbname']

    # Only do VersionId validation against the stage if a token is passed in
    if token:
        secret = service_client.get_secret_value(SecretId=arn, VersionId=token, VersionStage=stage)
    else:
        secret = service_client.get_secret_value(SecretId=arn, VersionStage=stage)
    plaintext = secret['SecretString']
    secret_dict = json.loads(plaintext)

    # Run validations against the secret
    if 'engine' not in secret_dict or secret_dict['engine'] != 'oracle':
        raise KeyError("Database engine must be set to 'oracle' in order to use this rotation lambda")
    for field in required_fields:
        if field not in secret_dict:
            raise KeyError("%s key is missing from secret JSON" % field)

    # Parse and return the secret JSON string
    return secret_dict
