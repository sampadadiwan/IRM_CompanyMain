# How to Deploy the app 

## Creating AMIs 
1. Check the source_ami in config/deploy/templates/appserver.ami.pkr.hcl. This must be changed based on the region, and if you have newer versions of the base AMI to use
2. Run the cmd 
`packer build -var ami_date=$(date +%Y-%m-%d) config/deploy/templates/appserver.pkr.hcl`
3. Note to run the above you must export the AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY for the env (staging or production)
`export AWS_ACCESS_KEY_ID=XXXXXX`
`export AWS_SECRET_ACCESS_KEY=YYYYYY`
4. Wait for the AMI to be create, once its done, check in the AWS console that it has been created under AMIs. This typically takes about 10+ mins

## Manually spinning up a server using the AMI created above
1.  