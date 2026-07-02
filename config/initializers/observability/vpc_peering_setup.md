# Cross-Region VPC Peering for Prometheus (IN → US)

Goal: allow the IN Prometheus server to scrape node_exporter (9100),
prometheus_exporter (9394), and mysqld_exporter (9104) on US servers
without exposing those ports to the public internet.

---

## Step 0 — Check for CIDR overlap (do this first)

VPC peering requires non-overlapping CIDR blocks. Both VPCs appear to use
10.0.x.x private IPs, which likely means both are 10.0.0.0/16 — if so,
peering will be blocked by AWS and you cannot proceed with this approach.

Check in the AWS Console → VPC → Your VPCs (switch region for each):

- IN VPC CIDR: _______________  (ap-south-1)
- US VPC CIDR: _______________  (us-east-1)

If they overlap (e.g. both 10.0.0.0/16): peering is not possible without
re-IP'ing one VPC. Use Option 2 (separate Prometheus per region + federation)
instead — see the architecture decision in the main README.

If they don't overlap: continue below.

---

## Step 1 — Create the peering connection (IN side)

In AWS Console → VPC → Peering Connections → Create Peering Connection:

- Name: caphive-in-us-prometheus
- VPC (Requester): [IN VPC ID]  region: ap-south-1
- Account: My account
- VPC (Accepter): [US VPC ID]  region: us-east-1

Or via CLI (run from any machine with AWS credentials):

```bash
aws ec2 create-vpc-peering-connection \
  --region ap-south-1 \
  --vpc-id <IN_VPC_ID> \
  --peer-vpc-id <US_VPC_ID> \
  --peer-region us-east-1
# Note the PeeringConnectionId returned (pcx-xxxxxxxxx)
```

---

## Step 2 — Accept the peering connection (US side)

Switch to us-east-1 in the Console → VPC → Peering Connections → select the
pending connection → Actions → Accept.

Or via CLI:

```bash
aws ec2 accept-vpc-peering-connection \
  --region us-east-1 \
  --vpc-peering-connection-id pcx-xxxxxxxxx
```

---

## Step 3 — Add routes to both route tables

Traffic needs a route in each VPC pointing cross-region traffic at the peering
connection.

**IN route table** (ap-south-1) — add a route so IN servers can reach US private IPs:

| Destination    | Target              |
|----------------|---------------------|
| [US VPC CIDR]  | pcx-xxxxxxxxx       |

**US route table** (us-east-1) — add a route so return traffic reaches IN:

| Destination    | Target              |
|----------------|---------------------|
| [IN VPC CIDR]  | pcx-xxxxxxxxx       |

In the Console: VPC → Route Tables → select the main route table for each VPC
→ Routes → Edit → Add route.

---

## Step 4 — Update US security groups

On each US server (app + DB), add inbound rules allowing only the IN Prometheus
server's private IP on the exporter ports:

| Port | Protocol | Source                        | Purpose              |
|------|----------|-------------------------------|----------------------|
| 9100 | TCP      | <IN Prometheus private IP>/32 | node_exporter        |
| 9394 | TCP      | <IN Prometheus private IP>/32 | prometheus_exporter  |
| 9104 | TCP      | <IN Prometheus private IP>/32 | mysqld_exporter (DB servers only) |

The IN Prometheus server is whichever EC2 instance runs the Prometheus Docker
container in ap-south-1 (check the observability AMI instance private IP).

Do NOT open these ports to 0.0.0.0/0 — that defeats the purpose.

---

## Step 5 — Find US private IPs for app servers

The deploy config uses public IPs for SSH, but Prometheus should scrape private
IPs over the peering connection. Find private IPs via:

```bash
aws ec2 describe-instances \
  --region us-east-1 \
  --filters "Name=ip-address,Values=54.147.171.162" \
  --query 'Reservations[*].Instances[*].PrivateIpAddress' \
  --output text

aws ec2 describe-instances \
  --region us-east-1 \
  --filters "Name=ip-address,Values=35.153.176.117" \
  --query 'Reservations[*].Instances[*].PrivateIpAddress' \
  --output text
```

---

## Step 6 — Update prometheus.prod.in.yml

Once you have the US private IPs, update prometheus.prod.in.yml to scrape
both IN and US targets from the single IN Prometheus instance:

```yaml
scrape_configs:
  - job_name: 'rails_app'
    static_configs:
      - targets:
          - '10.0.1.56:9394'          # IN primary app
          - '10.0.2.137:9394'         # IN second app
          - '<US_APP1_PRIVATE>:9394'  # US primary app
          - '<US_APP2_PRIVATE>:9394'  # US second app

  - job_name: node
    static_configs:
      - targets:
          - '10.0.1.56:9100'
          - '10.0.2.137:9100'
          - '10.0.3.182:9100'
          - '10.0.4.78:9100'
          - '<US_APP1_PRIVATE>:9100'
          - '<US_APP2_PRIVATE>:9100'
          - '10.0.3.214:9100'         # US primary DB
          - '10.0.4.28:9100'          # US replica DB

  - job_name: mysqld
    static_configs:
      - targets:
          - '10.0.3.182:9104'
          - '10.0.4.78:9104'
          - '10.0.3.214:9104'         # US primary DB
          - '10.0.4.28:9104'          # US replica DB
```

Then restart the IN Prometheus container to pick up the new config.

---

## Labelling IN vs US in Grafana

With both regions in one Prometheus, add a relabel rule per job so you can
filter dashboards by region:

```yaml
  - job_name: 'rails_app'
    static_configs:
      - targets: ['10.0.1.56:9394', '10.0.2.137:9394']
        labels:
          region: in
      - targets: ['<US_APP1_PRIVATE>:9394', '<US_APP2_PRIVATE>:9394']
        labels:
          region: us
```

This adds a `region` label to every metric so you can use
`{region="us"}` filters in Grafana panels and alerts.

---

## Cost estimate

Cross-region data transfer (ap-south-1 ↔ us-east-1): ~$0.02/GB.
Prometheus metrics are tiny — scraping 6 servers every 15s is roughly
50–100MB/day = under $2/month.
