## When we do a major upgrade remember to do these things
1. Stop alerts from betterstack
2. Disable monit, stop sidekiq and put up maintainence page by running the cmd
    `LB=true bundle exec cap production nginx:switch_maintenance`
4. Backup DB
5. Create primary instance from encrypted snapshot
6. Restore DB & reindex for ES
7. Create replica instance from encrypted snapshot
8. Restore DB
9. Restart console and check access
10. Enable Monit and jobs
    `LB=true bundle exec cap production nginx:switch_app`
12. Restart better stack
