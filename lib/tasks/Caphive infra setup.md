# Infra setup: How to

## Prerequisites
1. git clone https://github.com/ausangshukla/IRM
2. git clone https://github.com/ausangshukla/IRM-infra
3. Ensure you have pulumi installed (https://www.pulumi.com/)
    a. pulumi install plugin resurce aws

4. You have the AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY

## Philosophy
1. We will use IRM-infra to setup the entire infra
2. Then we will use the IP addresses from 1, to deploy our app
3. The we will get the S3 backup of our DB and load it into primary
4. Then we will load the DB into the replica
5. Then we will setup replication
6. Point DNS to the LB setup in 1

## Background Info
1. Every week the AMIs for the AppServer and DB-Redis-ES are created
2. Those AMIs are copied automatically to the AWS_BACKUP_REGION
3. We will recover in AWS_BACKUP_REGION, which will become the new AWS_REGION
4. All tasks are automated via rake (lib/aws.rake, lib/aws_utils.rb)

## Procedure
0. export AWS keys
    a. export AWS_REGION
    b. export AWS_ACCESS_KEY_ID=xxxxx, export AWS_SECRET_ACCESS_KEY=yyyyy
    c. These keys should be available in the application secrets
1.	Ensure latest AMIs are present in the region for AppServer and DB-Redis-ES
2.	RAILS_ENV=env rake "aws:setup_infra[env, AppServer, DB-Redis-ES, region]"
    a.	replace env with production or staging
    b.	replace region with ap-south-1 or ap-south-2 or us-east-1
    c.	ex. RAILS_ENV=production rake "aws:setup_infra[production, AppServer, DB-Redis-ES, ap-south-1]"

3.	The script will pause in the middle, after making changes to the deployment scripts
    a.	It will update the IP addresses in various files based on the new deployment
    b.	Review the changes
    c.	Restore the DB into the DB servers manually using the `db_backup_xtra_#{Rails.env}.sh restore primary`
    d.  Commit the changes as a branch ex new_infra_prod_07_18_2024
    e.	Put this name into the command line

Ex ouput is below

    Updating credentials for Rails.env = production, key = DB_HOST, value = 10.0.3.178
    Credentials updated successfully for Rails.env = production, key = DB_HOST.
    Updating credentials for Rails.env = production, key = DB_HOST_REPLICA, value = 10.0.4.212
    Credentials updated successfully for Rails.env = production, key = DB_HOST_REPLICA.
    Replacing IP addresses ["13.233.134.202", "52.66.51.85"] in file: /home/thimmaiah/work/IRM/config/deploy/production.rb
    IP addresses replaced successfully in file: /home/thimmaiah/work/IRM/config/deploy/production.rb

    #######################
    You need to commit your code, with the updated credentials, .env and deploy files, before deploying the app.
    Please enter branch name to deploy to continue once you have committed the code.
    #########################
    Enter branch name to continue or type 'exit' to abort...
    new_infra_prod_07_18_2024


4.	Then the script will deploy this branch to the new infra
5.	Setup replica using rake db:reset_replication on the appserver box
6.	Note: That if the last backup is before the last deployment to prod, it may not have the required migrations. This has to be run manually as the backup DB will be loaded
