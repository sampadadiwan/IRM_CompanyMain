
How to Implement Replication in Mysql Database

Steps to implement replication in mysql database

Spin up the Main (Primary/Master) sql server

On Master Sql server create a replication user with password
CREATE USER 'replication'@'%' IDENTIFIED WITH mysql_native_password BY 'password';

Now give Replication previleges to it
GRANT REPLICATION SLAVE ON *.* TO 'replication'@'%';

Run
SHOW MASTER STATUS\G
on Master sql server
\G just prints pretty

The Output should look something like this.
*************************** 1. row **************************
             File: mysql-bin.000003
         Position: 157
     Binlog_Do_DB: mydatabase
 Binlog_Ignore_DB: mysql
Executed_Gtid_Set:*

Note the file and position - we will have to specify this to slave for replication

Now on to the Replica (Secondary) sql server

Spin up another Mysql server. we will be using this as replica 1 (We can have multiple replicas)
On this run the 'Change master to' command
CHANGE MASTER TO MASTER_HOST='10.11.12.13', MASTER_USER='replication',MASTER_PORT=3306,  MASTER_PASSWORD='password', MASTER_LOG_FILE='binlog.000510', MASTER_LOG_POS=343817;

The MASTER_HOST should be an ip where the primary sql server is hosted - by default it would expect it at port 3306.
if its a different port then that will have to be specified in the change master command (look on mysql website)

And the MASTER_LOG_FILE and MASTER_LOG_POS by the values you got from the SHOW MASTER STATUS\G command on the master sql server


Make sure that this Master sql server machine's IP is accessible by the Replica server perhaps by trying
ping <ip>
in this case it would be
ping 10.11.12.13
and this will be run on the OS console and not inside the mysql shell
If so then we're good to go (expecting port 3306 to also be reachable or that can be tested specifically, e.g.
telnet 10.11.12.13 3306)

If this is successful then the Replica machine can access the Master sql server machine
SET GLOBAL server_id = 21; if both have same server ids
You can check the server_id using
SELECT @@server_id;
in mysql shell

Run START REPLICA or START SLAVE inside mysql shell on the Replica machine

Then run SHOW REPLICA STATUS\G
it should say waiting for master
