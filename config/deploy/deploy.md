# How to Deploy the app

## Creating AMIs
1. Note to run the above you must export the AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY for the env (staging or production)
`export AWS_ACCESS_KEY_ID=XXXXXX`
`export AWS_SECRET_ACCESS_KEY=YYYYYY`
`export AWS_REGION=us-east-1`

## Build all the AMIs in the region
2. rake packer:"build_env[dev,us,all]"

3. rake "aws:setup_infra[staging,AppServer,DB_Redis_ES,us-east-1,us]"

4. Once the servers are created and the infra is up. Login to both the DB servers using the web servers as jump hosts
   Copy the db_backup_xtra_#{Rails.env}.sh to the DB and Replica and run
   `db_backup_xtra_#{Rails.env}.sh restore_primary`

   This will load the DB into both primary and replica from the S3 backups

5. Follow the instructions in rake to commit and deploy

6. Reset Replication
  `RAILS_ENV=xxx bundle exec rake db:reset_replication`

  In some cases you need to log into the replica and restart replicaton
  `-- On the replica
  STOP REPLICA;
  CHANGE REPLICATION FILTER
    REPLICATE_IGNORE_TABLE = (IRM_staging.solid_cache_entries);
  START REPLICA;

  SHOW REPLICA STATUS\G
  `

7. New S3 buckets need CORS policy setup, else file uploads will fail

8. Now that the app is deployed we need to repoint the domain.
    1. The DNS for caphive.com is on AWS, but unfortunately in the dev account
    2. The DNS for the dev.altconnects.com is in godaddy
    3. Copy the AWS LB public DNS name (E.x appLb-production-82f2e1d-1367284319.ap-south-1.elb.amazonaws.com) and make the changes for the CNAME for
        a. caphive.com or (*.altconnects.com)
        b. *.caphive.com