# DR Drill Log

> **Rebuild (min)** is the time from the start of the recovery command to the
> stack passing `recovery:verify`. It is *not* end-to-end RTO: it excludes
> incident detection, the decision to declare a disaster, and DNS cutover plus
> TTL propagation. Per-run evidence reports are in `docs/dr_runs/`.

| Date | Stack | Variant | Region | Result | Rebuild (min) | Branch |
|---|---|---|---|---|---|---|
| 2026-07-08 19:24 | staging | in | ap-south-2 | FAILED | 1.2 | dr_drill_in_2026_07_08_1924 |
| 2026-07-08 19:29 | staging | in | ap-south-2 | FAILED | 3.7 | dr_drill_in_2026_07_08_1929 |
| 2026-07-08 19:36 | staging | in | ap-south-2 | FAILED | 1.3 | dr_drill_in_2026_07_08_1936 |
| 2026-07-08 19:40 | staging | in | ap-south-2 | FAILED | 5.1 | dr_drill_in_2026_07_08_1940 |
| 2026-07-08 19:51 | staging | in | ap-south-2 | FAILED | 5.1 | dr_drill_in_2026_07_08_1951 |
| 2026-07-08 20:03 | staging | in | ap-south-2 | PASSED | 8.0 | dr_drill_in_2026_07_08_2003 |
| 2026-07-09 18:39 | staging | in | ap-south-2 | PASSED | 14.7 | dr_drill_in_2026_07_09_1839 |
| 2026-07-10 10:56 | staging | in | ap-south-2 | FAILED | 16.8 | dr_drill_in_2026_07_10_1056 |
| 2026-07-10 11:38 | staging | in | ap-south-2 | FAILED | 15.2 | dr_drill_in_2026_07_10_1138 |
| 2026-07-10 11:57 | staging | in | ap-south-2 | FAILED | 10.0 | dr_drill_in_2026_07_10_1157 |
| 2026-07-10 12:07 | staging | in | ap-south-2 | FAILED | 2.7 | dr_drill_in_2026_07_10_1207 |
| 2026-07-10 12:11 | staging | in | ap-south-2 | FAILED | 2.3 | dr_drill_in_2026_07_10_1211 |
| 2026-07-10 12:18 | staging | in | ap-south-2 | FAILED | 16.5 | dr_drill_in_2026_07_10_1218 |
| 2026-07-10 13:00 | staging | in | ap-south-2 | PASSED | 8.7 | dr_drill_in_2026_07_10_1300 |
| 2026-07-10 15:07 | staging | in | ap-south-2 | FAILED | 17.5 | dr_drill_in_2026_07_10_1507 |
| 2026-08-29 13:15 | staging | in | ap-south-2 | FAILED | 2.6 | dr_drill_in_2026_08_29_1315 |
| 2026-08-29 13:18 | staging | in | ap-south-2 | FAILED | 13.8 | dr_drill_in_2026_08_29_1318 |
| 2026-08-29 13:39 | staging | in | ap-south-2 | FAILED | 11.8 | dr_drill_in_2026_08_29_1339 |
| 2026-08-29 13:51 | staging | in | ap-south-2 | FAILED | 4.1 | dr_drill_in_2026_08_29_1351 |
| 2026-08-29 13:56 | staging | in | ap-south-2 | FAILED | 7.4 | dr_drill_in_2026_08_29_1356 |
| 2026-08-29 14:08 | staging | in | ap-south-2 | FAILED | 5.4 | dr_drill_in_2026_08_29_1408 |
| 2026-08-29 14:20 | staging | in | ap-south-2 | FAILED | 15.5 | dr_drill_in_2026_08_29_1420 |
| 2026-08-29 14:36 | staging | in | ap-south-2 | FAILED | 4.1 | dr_drill_in_2026_08_29_1436 |
| 2026-08-29 14:43 | staging | in | ap-south-2 | FAILED | 5.0 | dr_drill_in_2026_08_29_1443 |
| 2026-08-29 14:50 | staging | in | ap-south-2 | FAILED | 5.6 | dr_drill_in_2026_08_29_1450 |
| 2026-08-29 15:02 | staging | in | ap-south-2 | FAILED | 6.9 | dr_drill_in_2026_08_29_1502 |
| 2026-08-29 15:37 | staging | in | ap-south-2 | FAILED | 13.0 | dr_drill_in_2026_08_29_1537 |
| 2026-08-29 15:52 | staging | in | ap-south-2 | FAILED | 2.5 | dr_drill_in_2026_08_29_1552 |
| 2026-08-29 16:06 | staging | in | ap-south-2 | FAILED | 2.5 | dr_drill_in_2026_08_29_1606 |
| 2026-08-29 16:16 | staging | in | ap-south-2 | PASSED | 11.5 | dr_drill_in_2026_08_29_1616 |
| 2026-08-29 16:31 | staging | in | ap-south-2 | PASSED | 11.1 | dr_drill_in_2026_08_29_1631 |
| 2026-08-29 16:47 | production | in | ap-south-2 | FAILED | 2.3 | dr_drill_production_in_2026_08_29_1647 |
| 2026-08-29 16:52 | production | in | ap-south-2 | FAILED | 7.1 | dr_drill_production_in_2026_08_29_1652 |
| 2026-08-29 17:02 | production | in | ap-south-2 | FAILED | 8.4 | dr_drill_production_in_2026_08_29_1702 |
| 2026-08-29 17:13 | production | in | ap-south-2 | FAILED | 2.4 | dr_drill_production_in_2026_08_29_1713 |
