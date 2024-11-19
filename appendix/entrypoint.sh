#!/bin/bash
service munge restart
service mysql restart

mysql <<EOF
create user 'jc'@'localhost' identified by 'jc@1234';
create database slurm_acct_db;
grant all PRIVILEGES on slurm_acct_db.* TO 'jc'@'localhost' with grant option;
EOF

service slurmdbd restart
service slurmctld restart
service slurmd restart

/usr/sbin/sshd -D
